-- ============================================================
-- Portal Mayorista Balling LatAm — esquema Supabase
-- Lista de precios única · stock real · cuenta corriente · envíos
-- ============================================================

create extension if not exists "uuid-ossp";

-- ---------- perfiles / roles ----------
create table perfiles (
  id uuid primary key references auth.users on delete cascade,
  rol text not null default 'mayorista' check (rol in ('mayorista','admin')),
  creado_en timestamptz default now()
);

create table clientes (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid unique references auth.users on delete set null,
  razon_social text not null,
  cuit text,
  nombre_contacto text,
  email text,
  telefono text,
  direccion text,
  localidad text,
  provincia text,
  pais text default 'AR',
  descuento_pct numeric(5,2) not null default 0,   -- descuento sobre lista única
  limite_credito numeric(14,2) not null default 0,
  minimo_compra numeric(14,2) not null default 0,  -- monto mínimo por pedido
  activo boolean not null default true,
  creado_en timestamptz default now()
);

-- ---------- catálogo ----------
create table productos (
  id uuid primary key default uuid_generate_v4(),
  sku_base text unique not null,
  modelo text not null,
  serie text,
  categoria text,               -- palos, guantes, bolsos, protección, accesorios
  descripcion text,
  foto_url text,
  precio_lista numeric(14,2) not null,   -- lista única, sin IVA
  iva_pct numeric(5,2) not null default 21,
  unidades_por_bulto int not null default 1,
  minimo_unidades int not null default 1,
  orden int default 0,
  activo boolean not null default true
);

create table variantes (
  id uuid primary key default uuid_generate_v4(),
  producto_id uuid not null references productos on delete cascade,
  sku text unique not null,
  talle text,
  color text,
  stock int not null default 0,
  stock_reservado int not null default 0,
  activo boolean not null default true
);
create index on variantes (producto_id);

-- stock disponible = stock - reservado
create view v_variantes_disponibles as
select v.*, (v.stock - v.stock_reservado) as disponible
from variantes v;

-- ---------- pedidos ----------
create sequence pedido_numero_seq start 1000;

create table pedidos (
  id uuid primary key default uuid_generate_v4(),
  numero int not null default nextval('pedido_numero_seq'),
  cliente_id uuid not null references clientes,
  estado text not null default 'borrador'
    check (estado in ('borrador','enviado','confirmado','preparacion','despachado','entregado','cancelado')),
  subtotal numeric(14,2) not null default 0,
  descuento numeric(14,2) not null default 0,
  iva numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  notas text,
  creado_en timestamptz default now(),
  enviado_en timestamptz,
  confirmado_en timestamptz
);
create index on pedidos (cliente_id, estado);

create table pedido_items (
  id uuid primary key default uuid_generate_v4(),
  pedido_id uuid not null references pedidos on delete cascade,
  variante_id uuid not null references variantes,
  sku text not null,
  descripcion text not null,
  cantidad int not null check (cantidad > 0),
  precio_unit numeric(14,2) not null,
  descuento_pct numeric(5,2) not null default 0,
  subtotal numeric(14,2) not null
);
create index on pedido_items (pedido_id);

-- ---------- envíos ----------
create table envios (
  id uuid primary key default uuid_generate_v4(),
  pedido_id uuid not null references pedidos on delete cascade,
  transporte text,
  tracking text,
  estado text not null default 'pendiente'
    check (estado in ('pendiente','despachado','en_transito','entregado','incidencia')),
  bultos int default 1,
  fecha_despacho date,
  fecha_estimada date,
  fecha_entrega date,
  observaciones text
);
create index on envios (pedido_id);

-- ---------- cuenta corriente ----------
create table cc_movimientos (
  id uuid primary key default uuid_generate_v4(),
  cliente_id uuid not null references clientes,
  fecha date not null default current_date,
  tipo text not null check (tipo in ('cargo','pago','nota_credito','ajuste')),
  concepto text not null,
  pedido_id uuid references pedidos,
  comprobante text,
  importe numeric(14,2) not null,   -- cargo (+) / pago (-)
  creado_en timestamptz default now()
);
create index on cc_movimientos (cliente_id, fecha);

create view v_saldos as
select c.id as cliente_id, c.razon_social, c.limite_credito,
       coalesce(sum(m.importe),0) as saldo,
       c.limite_credito - coalesce(sum(m.importe),0) as credito_disponible
from clientes c
left join cc_movimientos m on m.cliente_id = c.id
group by c.id;

-- ============================================================
-- Lógica: al confirmar un pedido → descuenta stock + carga en CC
-- ============================================================
create or replace function fn_confirmar_pedido() returns trigger as $$
begin
  if new.estado = 'confirmado' and old.estado <> 'confirmado' then
    update variantes v
       set stock = v.stock - i.cantidad,
           stock_reservado = greatest(v.stock_reservado - i.cantidad, 0)
      from pedido_items i
     where i.pedido_id = new.id and i.variante_id = v.id;

    insert into cc_movimientos (cliente_id, tipo, concepto, pedido_id, importe)
    values (new.cliente_id, 'cargo', 'Pedido #' || new.numero, new.id, new.total);

    insert into envios (pedido_id) values (new.id);
    new.confirmado_en := now();
  end if;

  if new.estado = 'enviado' and old.estado = 'borrador' then
    -- reserva stock al enviar el pedido
    update variantes v
       set stock_reservado = v.stock_reservado + i.cantidad
      from pedido_items i
     where i.pedido_id = new.id and i.variante_id = v.id;
    new.enviado_en := now();
  end if;

  if new.estado = 'cancelado' and old.estado in ('enviado','confirmado') then
    update variantes v
       set stock_reservado = greatest(v.stock_reservado - i.cantidad, 0)
      from pedido_items i
     where i.pedido_id = new.id and i.variante_id = v.id;
  end if;

  return new;
end; $$ language plpgsql;

create trigger trg_confirmar_pedido
  before update on pedidos
  for each row execute function fn_confirmar_pedido();

-- recalcular totales del pedido
create or replace function fn_recalcular_pedido() returns trigger as $$
declare pid uuid; sub numeric; iv numeric; desc_pct numeric;
begin
  pid := coalesce(new.pedido_id, old.pedido_id);
  select coalesce(sum(subtotal),0) into sub from pedido_items where pedido_id = pid;
  select c.descuento_pct into desc_pct
    from pedidos p join clientes c on c.id = p.cliente_id where p.id = pid;
  iv := round(sub * 0.21, 2);
  update pedidos
     set subtotal = sub,
         descuento = round(sub * coalesce(desc_pct,0) / 100, 2),
         iva = iv,
         total = sub - round(sub * coalesce(desc_pct,0)/100, 2) + iv
   where id = pid;
  return null;
end; $$ language plpgsql;

create trigger trg_recalcular_pedido
  after insert or update or delete on pedido_items
  for each statement execute function fn_recalcular_pedido();

-- ============================================================
-- RLS — cada mayorista ve solo lo suyo; admin ve todo
-- ============================================================
create or replace function es_admin() returns boolean as $$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'admin');
$$ language sql security definer stable;

create or replace function mi_cliente_id() returns uuid as $$
  select id from clientes where user_id = auth.uid();
$$ language sql security definer stable;

alter table clientes        enable row level security;
alter table productos       enable row level security;
alter table variantes       enable row level security;
alter table pedidos         enable row level security;
alter table pedido_items    enable row level security;
alter table envios          enable row level security;
alter table cc_movimientos  enable row level security;
alter table perfiles        enable row level security;

create policy "perfil propio" on perfiles for select using (id = auth.uid() or es_admin());

create policy "cliente ve su ficha" on clientes for select
  using (user_id = auth.uid() or es_admin());
create policy "admin edita clientes" on clientes for all
  using (es_admin()) with check (es_admin());

create policy "catalogo visible" on productos for select using (activo or es_admin());
create policy "admin edita productos" on productos for all
  using (es_admin()) with check (es_admin());
create policy "variantes visibles" on variantes for select using (true);
create policy "admin edita variantes" on variantes for all
  using (es_admin()) with check (es_admin());

create policy "pedidos propios" on pedidos for select
  using (cliente_id = mi_cliente_id() or es_admin());
create policy "crear pedido propio" on pedidos for insert
  with check (cliente_id = mi_cliente_id());
create policy "editar borrador propio" on pedidos for update
  using ((cliente_id = mi_cliente_id() and estado in ('borrador','enviado')) or es_admin());

create policy "items propios" on pedido_items for all
  using (exists (select 1 from pedidos p where p.id = pedido_id
                 and (p.cliente_id = mi_cliente_id() or es_admin())))
  with check (exists (select 1 from pedidos p where p.id = pedido_id
                 and (p.cliente_id = mi_cliente_id() or es_admin())));

create policy "envios propios" on envios for select
  using (exists (select 1 from pedidos p where p.id = pedido_id
                 and (p.cliente_id = mi_cliente_id() or es_admin())));
create policy "admin edita envios" on envios for all
  using (es_admin()) with check (es_admin());

create policy "cc propia" on cc_movimientos for select
  using (cliente_id = mi_cliente_id() or es_admin());
create policy "admin edita cc" on cc_movimientos for all
  using (es_admin()) with check (es_admin());

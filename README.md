# Portal Mayorista Balling LatAm

Portal B2B de pedidos para distribuidores de Balling en Latinoamérica.

**Demo:** https://lucasbarranco-blip.github.io/portal-balling/

Accesos de prueba: `demo` / `demo` (mayorista) · `admin` / `admin` (representante).

## Qué resuelve

- **Catálogo** con matriz colorway × talle: el mayorista carga cantidades como en una planilla, con totales por fila, columna y modelo.
- **Precio mayorista y PVP** en la misma línea, para que calcule margen sin salir de la app.
- **Stock en vivo**: cada input topea en el disponible y marca stock bajo.
- **Pedido en dos etapas**: lo que se tipea queda en borrador hasta *Agregar al pedido*; después se revisa en *Mi pedido* antes de enviar.
- **Pedidos recurrentes**: plantillas de reposición con frecuencia, que se cargan de una y se ajustan solas al stock actual. También se puede duplicar cualquier pedido del historial.
- **Cuenta corriente** con debe/haber/saldo, límite y crédito disponible.
- **Envíos** con transporte, tracking, bultos y fecha estimada.
- **Panel del representante**: pedidos entrantes, confirmación (descuenta stock y carga en cuenta corriente), stock y cobranzas.

## Estructura

| Archivo | Qué es |
|---|---|
| `index.html` | La app completa, single-file. Sin build. |
| `schema.sql` | Esquema de Supabase: tablas, vistas, triggers y RLS. |

## Puesta en marcha

1. Correr `schema.sql` en el SQL editor de Supabase.
2. Completar `SUPABASE_URL` y `SUPABASE_ANON_KEY` arriba del `<script>` en `index.html`.

Con esas constantes vacías la app corre en **modo demo** con el catálogo real de ballinghockey.com.ar y datos de prueba en memoria.

## Pendientes de definición

- `FACTOR_MAYORISTA` (hoy 0,55) es un placeholder: reemplazar por la lista mayorista real.
- Definir si el mínimo de compra es por monto o por bulto/curva.
- Notificación del pedido al representante (WhatsApp o mail vía Cloudflare Worker).
- Tabla `plantillas` para persistir los pedidos recurrentes.

## Tipografía

Misma que ballinghockey.com.ar: **Instrument Sans** (Google Fonts) para UI y títulos, y **Vaud** para texto corrido y precios. Vaud es licenciada — hay un bloque `@font-face` comentado en el CSS para self-hostearla si se cuenta con la licencia.
# portal-balling
Portal B2B de pedidos mayoristas para distribuidores de Balling en Latinoamerica. Single-file HTML + Supabase.

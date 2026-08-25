# Notas de integración MacGameVideoFix ↔ Procyon

## 2026-08-25 — primera corrida del fork con motor parcheado

Motor: copia parcheada de CrossOver Preview 27 (`27.0.0.40921`), creada por el
fork con el paso de GStreamer desactivado. Bottle aislada en
`…/Application Support/Procyon/CXPBottles/Steam`.

**Ghost of Tsushima**: arranca y corre. Primer juego lanzado por el fork.

**NINJA GAIDEN 4**: arranca y *renderiza* — el HUD da D3D12, 1920x1242, 59.62 FPS,
`Game Porting Toolkit 3.0` — y entonces muestra su propio diálogo:

> Windows is missing required components for the game to function properly.
> Please make sure to install Windows Media Foundation and the VP9 Codec.
> The game will now exit.

Interpretación: es la **compuerta de `MFTEnumEx`**, no una carencia de códec. El
juego consulta Media Foundation por un decodificador VP9 antes de tocar un solo
fichero de vídeo, y si la enumeración vuelve vacía se cierra él mismo. El
staging de codecs no responde a esa pregunta: aporta el demuxer Matroska y los
decoders de libav, pero la compuerta se contesta desde dentro del proceso, que
es lo que hace `install-ng4-fix.sh` con su proxy sobre `dstorage.dll`.

O sea que NG4 aquí está *mejor* que antes —llega a dibujar— y le falta
exactamente su fix, que no está instalado en esta bottle.

**Por qué no se le puede instalar hoy**: los instaladores tienen la ruta clavada

    BOTTLES="$HOME/Library/Application Support/CrossOver/Bottles"

y esta bottle vive bajo `Application Support/Procyon/CXPBottles`. Hasta que
acepten una bottle explícita, ningún juego con puente se puede probar en el
fork. Es el siguiente trabajo en la lista.

**Dato lateral**: el HUD dice GPTK 3.0 porque Procyon reinstala d3dMetal en
*cada* lanzamiento y su rama por defecto es la versión 3
(`Launcher.swift`, `switch options!.cxGraphicsBackend` → `default: installd3dMetal(version: "3")`).
Para NG4 da la casualidad de que 3.0 es la correcta; para Life is Strange no lo
sería.

**NieR Replicant**: funciona. Y sirve de validación del staging, por eliminación:

- el motor parcheado trae `libgstmatroska.dylib` y **ningún** `libgstlibav`
- el vídeo de NieR es ASF con FourCC `WMV2` (medido: GUID de cabecera ASF en
  0x18, tras la cabecera MARC de 0x18 bytes, dos objetos Stream Properties)
- `WMV2` sólo lo decodifica `avdec_wmv2`, que vive únicamente en `libgstlibav`

La única copia de `libgstlibav` en ese proceso es la del staging, así que si el
vídeo se ve, el staging está montado y funcionando contra el motor parcheado.

## Estado de la cadena, extremo a extremo

    motor parcheado sin sustituir su GStreamer   ✓
    staging contra ESE bundle, por ruta          ✓
    GST_PLUGIN_PATH en la bottle aislada         ✓
    el juego reproduce su vídeo                  ✓

## Lo que falta

1. Los instaladores de puentes aceptan sólo `…/CrossOver/Bottles`. Sin eso, NG4,
   Kingdom Hearts y los demás títulos con puente no se pueden probar en el fork.
2. `stage-codecs.sh` sólo genera `x86_64`. Una bottle ARM no tendría decoders.
3. Procyon reinstala d3dMetal en cada lanzamiento con la versión 3 por defecto;
   los títulos que necesitan 4.0b2 quedarían servidos con la equivocada.

**Persona 5 Strikers**: funciona. Segunda validación independiente del staging, y
con otro códec: su vídeo es ASF con **VC-1**, que sólo decodifica `avdec_vc1`,
también exclusivo de `libgstlibav`. Dos juegos, dos códecs distintos (WMV2 y
VC-1), la misma y única fuente posible.

**NINJA GAIDEN 4**, revisión de la nota anterior: su fix SÍ estaba instalado
(`dstorage.dll` + `dstorage_real.dll`, `--status` dice `installed`) y no necesita
registro, porque Wine no implementa `dstorage` y el DLL de la carpeta del juego
se carga solo. Lo más probable es que fallara porque Steam se lanzó **antes** de
escribir `GST_PLUGIN_PATH` en la bottle, así que ese árbol de procesos corría con
el entorno viejo. Pendiente de reintentar con Steam relanzado.

## Resuelto: los instaladores ya encuentran cualquier bottle

`install-nier-bridge.sh` e `install-kh-bridge.sh` tenían la raíz de bottles
clavada. Ahora recorren varias, en orden: `MGVF_BOTTLES` si se define, la
preferencia `BottleDir` de CrossOver, la raíz por defecto, y la de Procyon
(`Application Support/Procyon/CXPBottles`). El filtro por `libraryfolders.vdf`
se mantiene, así que añadir raíces no produce falsos positivos: sólo reciben el
override las bottles que de verdad contienen esa biblioteca de Steam.

## Bottles ARM en CrossOver 27 (el prerrequisito de codecs ya está hecho)

CrossOver 27 instala wine para ARM, y ese wine sólo sirve con una bottle ARM. Así
que el fork debe permitir crear bottles ARM cuando el motor es 27. Medido en
Preview 27.0.0.40921:

    lib/wine/aarch64-windows   799 ficheros
    lib/wine/aarch64-unix       35
    lib/aarch64                 94   (incluye su propio libMoltenVK)

**Va emparejado con el hueco de arquitectura del staging, y no se puede hacer uno
sin el otro.** Hoy `stage-codecs.sh` sólo genera `x86_64`:

    motor, plugins GStreamer   x86_64: 19   aarch64: 19   libgstlibav en ambos: 0
    framework libgstlibav      x86_64 + arm64  (universal, verificado con lipo)
    staging                    sólo x86_64

Y el caché `gstreamer-1.0-registry.aarch64.bin` tiene **cero** entradas `avdec_*`.

Consecuencia: una bottle ARM arrancaría, pero Persona 5 Strikers, Nioh, Nioh 2,
Devil May Cry 5, RESIDENT EVIL 2 y RESIDENT EVIL 3 se quedarían sin decodificador
de VC-1, WMV3 y WMA. Habilitar bottles ARM sin etapar aarch64 es una regresión
para seis títulos que hoy funcionan.

El material existe: basta hacer thin de los mismos dos plugins y sus dependencias
contra `lib/aarch64` del motor. Es hueco de script, no de material.

**Actualización (2026-08-25, misma tarde)**: el staging aarch64 está implementado y
construido. Verificado en disco: tres motores con directorio `aarch64`, el `.map`
pasó de 2 a 8 líneas, y el symlink del núcleo apunta a `lib/aarch64/libgstreamer-1.0.0.dylib`
del motor, que es arm64 puro — un solo núcleo por proceso, que es la premisa del
diseño. Plugins y FFmpeg quedan universales (x86_64 + arm64): cuesta disco, no
corrección.

Con eso el prerrequisito está cerrado y la creación de bottles ARM deja de ser una
regresión para los seis títulos de VC-1/WMV3/WMA. Lo que queda para las bottles ARM
es lo de la otra nota: `WineArch` se fija al crear, así que elegir ARM tiene que
abrir *otra* bottle, no la de por defecto; esa bottle necesita ver la biblioteca de
Steam; y el override de registro se instala por bottle, no por juego.

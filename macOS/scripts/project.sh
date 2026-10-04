# Shared by the working build and the exported project.
APP_VERSION="0.20.0"
APP_BUILD="42"
APP_MINIMUM_MACOS="13.0"
APP_IDENTIFIER="local.cursorwash.probe"
GITHUB_REPOSITORY="Oladii/CursorWasher"
APP_INSTALLER_FILENAME="CursorWasher-Installer.dmg"

APP_RUNTIME_SOURCES=(
  CursorSession WashPlayback BucketLayout WidgetGesture WashClickSequence WashView
  WaterMotion WaterSurface PaintedWaterDrop ReturnOverlay WashAnimation
  SinkAnimation CursorGeometry CursorSprite BucketHitMap
  TransparentContentView StatusBarIcon main
)
APP_RUNTIME_RESOURCES=(
  bucket-dry.png water-calm-source.png water-highlights-source.png app-icon.png installer-layout.dsstore
)

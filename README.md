# CursorWasher

[English](README.en.md)

## Зачем

Трогал курсором что-то неприятное, а после хочешь хорошенько помыть его с мылом? Один клик — и курсор как новенький. Чистым курсором снова можно трогать свои файлы и гладить макеты.

[Скачать для macOS](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-Installer.dmg) · [Скачать для Windows](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher.zip)

Исходники отдельно: [macOS](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-macOS-Sources.zip) · [Windows](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-Windows-Sources.zip)

![Ведёрко для мытья курсора](media/cursor-washer.gif)

## Как запустить на macOS

![Предупреждение macOS при запуске CursorWasher](https://cdsassets.apple.com/live/7WUAS350/images/macos/sequoia/locale/ru-ru/macos-sequoia-app-not-opened-could-not-verify-free-from-malware.png)

Я простой сельский парень, поэтому у ведра пока нет подписи Developer ID, а значит macOS заблокирует скачанное приложение. [Инструкция Apple по разрешению запуска](https://support.apple.com/en-ie/102445).

## Что умеет

- Мыть курсор.
- Поднимать настроение.
- Можно расположить ведро поверх всех окон или оставить на рабочем столе.

## Что не умеет

- Покупать пиво.
- Делать что-либо полезное.

## Установка

В чистовом комплекте установщик находится в `App/CursorWasher-Installer.dmg`. Скачать установщик можно со [страницы релизов](https://github.com/Oladii/CursorWasher/releases).

1. Откройте DMG.
2. Перетащите `CursorWasher` в папку `Applications` («Программы») в открывшемся окне.
3. Запустите приложение из «Программ».
4. Настройте автозапуск, если ведро нужно часто.

## Сборка

Если хочется собрать ведро самому (зачем?), скачайте исходники.

Потребуются инструменты разработки Apple с Swift и macOS SDK.

```sh
bash scripts/package.sh
```

Команда собирает приложение и установочный DMG в `Build/`.

Чтобы собрать только приложение:

```sh
bash scripts/build.sh
```

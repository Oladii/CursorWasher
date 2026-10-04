# CursorWasher

[English](README.en.md)

## Зачем

Трогал курсором что-то неприятное, а после хочешь хорошенько помыть его с мылом? Один клик — и курсор как новенький. Чистым курсором снова можно трогать свои файлы и гладить макеты.

[Скачать для macOS](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-Installer.dmg) · [Скачать для Windows](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher.zip)

![Ведёрко для мытья курсора](media/cursor-washer.gif)

## Как запустить на macOS

![Предупреждение macOS при запуске CursorWasher](https://cdsassets.apple.com/live/7WUAS350/images/macos/sequoia/locale/ru-ru/macos-sequoia-app-not-opened-could-not-verify-free-from-malware.png)

Я простой сельский парень, поэтому у ведра пока нет подписи Developer ID, а значит macOS заблокирует скачанное приложение. [Инструкция Apple по разрешению запуска](https://support.apple.com/en-ie/102445).

## Как запустить на Windows

Windows-версия пока не подписана цифровой подписью издателя, поэтому SmartScreen может показать сообщение «Система Windows защитила ваш компьютер».

Если вы скачали приложение из [официального релиза CursorWasher](https://github.com/Oladii/CursorWasher/releases/latest), нажмите **«Подробнее» → «Выполнить в любом случае»**.

## Что умеет

- Мыть курсор.
- Поднимать настроение.
- Можно расположить ведро поверх всех окон или оставить на рабочем столе.

## Что не умеет

- Покупать пиво.
- Делать что-либо полезное.

## Установка

### macOS

Скачайте [установщик для macOS](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-Installer.dmg). Нужна macOS 13 или новее.

1. Откройте DMG.
2. Перетащите `CursorWasher` в папку `Applications` («Программы») в открывшемся окне.
3. Запустите приложение из «Программ».
4. Настройте автозапуск, если ведро нужно часто.

### Windows

Скачайте [CursorWasher.zip](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher.zip). Нужен .NET Framework 4.8.

1. Распакуйте архив в отдельную папку.
2. Запустите `CursorWasher.exe`. Установщик и права администратора не нужны.

## Самостоятельная сборка

Если хочется собрать ведро самому (зачем?), скачайте исходники.

### macOS

[Скачать исходники для macOS](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-macOS-Sources.zip).

Потребуются инструменты разработки Apple с Swift и macOS SDK.
В репозитории перейдите в папку `macOS`, а в отдельном архиве исходников — в папку со `scripts`.

```sh
bash scripts/package.sh
```

Команда собирает приложение и установочный DMG в `Build/`.

Чтобы собрать только приложение:

```sh
bash scripts/build.sh
```

### Windows

[Скачать исходники для Windows](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-Windows-Sources.zip).

Потребуется .NET Framework 4.8; внешние пакеты не нужны. Перейдите в папку `Windows` в репозитории или распакованном архиве и выполните в PowerShell:

```powershell
.\scripts\build.ps1 -Test -Package
```

Приложение появится в `App`, архив — в `.build/Packages/CursorWasher.zip`.

Сборка и проверки Windows также выполняются в [GitHub Actions](https://github.com/Oladii/CursorWasher/actions/workflows/windows.yml).
ZIP доступен в артефактах успешного запуска; эти сборки пока не подписаны.

## Удаление

### macOS

В меню приложения выберите **Quit**, затем удалите `CursorWasher` из «Программ».
Если вы добавляли его в объекты входа, уберите оттуда тоже.
Чтобы также удалить сохранённый слой окна, после выхода выполните в Терминале:

```sh
defaults delete local.cursorwash.probe
```

### Windows

Выберите **Quit** в меню значка трея, затем удалите папку с приложением и созданный для него ярлык.
Локальные настройки и журнал (`CursorWasher.settings`, `CursorWasher.log`) находятся в той же папке.

## Лицензия и конфиденциальность

[MIT License](LICENSE) — Copyright (c) 2026 Oladii.
[Сведения о приватности](PRIVACY.md): приложение работает локально и не отправляет данные по сети.

## Code signing policy

[Политика подписи](CODE_SIGNING.md). Сейчас приложение не подписано; подключение SignPath ещё не завершено.

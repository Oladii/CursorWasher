# Privacy / Конфиденциальность

## English

CursorWasher works locally. The application does not make network requests,
upload cursor images, send analytics or crash reports, or check for updates.
There are no accounts or advertising services in the application.

To draw the animation, the application reads the current pointer image and
position and the operating system's display/accessibility settings. These are
used locally. Windows also reads the selected cursor and taskbar theme from
the current user's registry settings; it does not replace the system cursor
scheme or change those registry settings.

Windows stores `CursorWasher.settings` and `CursorWasher.log` beside the EXE.
Settings contain the bucket position and window layer. Logs contain local
diagnostic information, such as display scale, cursor image dimensions and
errors. These files are not uploaded and can be deleted after quitting the app.
Avoid sharing a diagnostic log without reviewing its contents.

macOS stores the window layer in the app's local preferences under
`local.cursorwash.probe`. The application does not transmit those preferences.
macOS diagnostic events are written to the operating system's local unified log.

Downloading releases, visiting documentation links or using GitHub and SignPath
is governed by the respective services' privacy policies. Those services are
not contacted by the running CursorWasher application.

## Русский

CursorWasher работает локально. Приложение не делает сетевых запросов, не
отправляет изображения курсора, аналитику или отчёты об ошибках и не проверяет
обновления. Аккаунтов и рекламных сервисов в приложении нет.

Для анимации приложение читает изображение и положение курсора, параметры
экрана и универсального доступа. Всё используется локально. В Windows также
читаются выбранный курсор и тема панели задач из пользовательских настроек
реестра; системная схема курсоров и эти настройки не меняются.

Windows сохраняет `CursorWasher.settings` и `CursorWasher.log` рядом с EXE.
В настройках находятся положение ведра и слой окна. В журнале — локальная
диагностика: масштаб экрана, размеры изображения курсора и ошибки. Эти файлы
никуда не отправляются; после выхода из приложения их можно удалить.
Перед передачей журнала другому человеку проверьте его содержимое.

macOS сохраняет слой окна в локальных настройках приложения
`local.cursorwash.probe`. Эти настройки не передаются по сети.
Диагностические события macOS записываются в локальный системный журнал.

Скачивание релизов, переход по ссылкам документации и работа с GitHub или
SignPath регулируются правилами соответствующих сервисов. Запущенное
приложение CursorWasher к ним не обращается.

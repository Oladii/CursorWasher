# Code signing policy

## Current status

CursorWasher releases are currently unsigned. Preparation for SignPath Foundation
is in progress; the project has not yet been accepted and no SignPath certificate
or signing credentials are configured.

The Windows build workflow compiles and tests the published source on a
GitHub-hosted Windows runner. Successful runs retain an unsigned Windows ZIP as
a GitHub Actions artifact linked to its commit and workflow run.

## Maintainer roles

- Author and committer: [Oladii](https://github.com/Oladii).
- Reviewer of external contributions: [Oladii](https://github.com/Oladii).
- Release signing approver: [Oladii](https://github.com/Oladii).

External contributions must be reviewed before being included in a signed
release. Maintainers must use multi-factor authentication for GitHub and
SignPath before production signing is enabled. Each release signing request
must be approved manually by the release signing approver.

## Planned signing process

After enrollment is approved, Windows releases will use code signing provided
by [SignPath.io](https://signpath.io/), with a certificate issued to
[SignPath Foundation](https://signpath.org/). The required provider attribution
will be added to signed release notes when the service is active.

Only release builds of `CursorWasher.exe` from reviewed commits on `main` may
be submitted for production signing. SignPath must verify that the artifact
was built by the repository's GitHub-hosted workflow. Pull request artifacts,
diagnostic executables and third-party binaries are excluded from production
signing. Signing credentials must be kept in protected service settings or
GitHub secrets and must never be committed to this repository.

Before publication, the approved signed EXE must pass Authenticode verification,
and its product name and version must match the reviewed build. The signed file
is then packaged with the launch instructions and MIT license. A release is
described as signed only after verification succeeds.

## Privacy

CursorWasher does not send data over the network. See the [privacy information](PRIVACY.md)
for local settings and logs. GitHub and SignPath process repository/build data
when maintainers use their services; they are not application dependencies.

## Кратко по-русски

Сейчас релизы не подписаны. Сборка Windows выполняется в GitHub Actions;
подключение SignPath ещё не завершено. Oladii отвечает за код, проверку внешних
изменений и ручное подтверждение подписи релизов. Перед включением подписи
нужна двухфакторная аутентификация в GitHub и SignPath. Подписываться будут
только проверенные сборки из `main`; перед публикацией подпись проверяется.
Приложение не отправляет данные по сети: [подробнее](PRIVACY.md).

# Hols для iPhone и iPad

Нативное приложение (Swift, UIKit + WKWebView) для мессенджера https://hols-chat.ru. iOS 15+.

## Что внутри
- Вход и чаты сохраняются, полный экран с «чёлкой», тёмный запуск.
- Файлы: 📎 → «Файл» открывает выбор iOS (Файлы / Фото / камера). Скачанный файл открывается в меню «Поделиться»:
  «Сохранить в Файлы», AirDrop, Telegram… Сверху — полоска прогресса.
- Звонки и голосовые: доступ к микрофону и камере после системного вопроса, звук идёт и в беззвучном режиме.
- Ссылки на другие сайты — в Safari; `hols://username` и ссылки hols-chat.ru — внутри.
- Свайп от левого края закрывает окно или открытый чат.
- Экран «Нет соединения» с автоповтором; если iOS выгрузит страницу, она перезапустится сама.

## Как собрать без Mac — GitHub Actions
1. Создайте репозиторий на GitHub (можно приватный) и загрузите в него эту папку (вместе с `.github`).
2. Вкладка **Actions** → «iOS build» → Run workflow. Через ~5 минут в разделе Artifacts появится `Hols-iOS`
   с файлом `Hols-unsigned.ipa`.

## Как поставить на свой iPhone
**Бесплатно (Apple ID):** установите Sideloadly на Windows, подключите iPhone кабелем, перетащите
`Hols-unsigned.ipa`, введите свой Apple ID → Start. На iPhone: Настройки → Основные → VPN и управление
устройством → доверять. С бесплатным Apple ID приложение работает 7 дней, потом Sideloadly переподписывает.

**Для всех (аккаунт Apple Developer, $99/год):** добавьте в Secrets репозитория `P12_BASE64`, `P12_PASSWORD`,
`PROFILE_BASE64`, `TEAM_ID` — workflow сам соберёт подписанный `Hols-signed.ipa` (ad-hoc). Для TestFlight / App
Store — откройте проект в Xcode (`xcodegen generate`) → Product → Archive → Distribute.

## На Mac
`brew install xcodegen && xcodegen generate && open Hols.xcodeproj` → выберите свой Team → Run.

# Komet — Документация разработчика

> Версия: 0.4.1+ · Платформы: Android, iOS (частично)

---

## Содержание

1. [Система плагинов](#1-система-плагинов)
2. [JavaScript API плагина](#2-javascript-api-плагина)
3. [Структура .kometplugin](#3-структура-kometplugin)
4. [Пример плагина](#4-пример-плагина)
5. [Bluetooth Mesh P2P](#5-bluetooth-mesh-p2p)
6. [Разрешения плагинов](#6-разрешения-плагинов)

---

## 1. Система плагинов

Плагины Komet — это ZIP-архивы с расширением `.kometplugin`. Они могут:

- Добавлять разделы в настройки
- Изменять константы приложения (цвета, URL, задержки)
- Заменять стандартные экраны
- Выполнять JavaScript-логику (script.js)
- Перехватывать входящие и исходящие сообщения
- Добавлять пункты в меню ⋮ открытого чата

### Установка

Нажмите `+` в Настройки → Плагины и выберите `.kometplugin` файл.

### Жизненный цикл

```
Установка → Разрешения (пользователь) → Включён → JS-движок запущен
Выключение → JS-движок остановлен
Удаление  → JS-движок остановлен + файлы удалены
```

---

## 2. JavaScript API плагина

Когда плагин включён и содержит `script.js`, Komet запускает изолированный
JavaScript-движок (headless WebView). Скрипт получает объект `komet` с
полным API.

### komet.log(...args)

Вывод в debug-лог приложения.

```js
komet.log('Plugin started!', new Date().toISOString());
```

### komet.storage

Персистентное key-value хранилище плагина (пережи вает перезапуск).

```js
// Записать
await komet.storage.set('counter', 42);

// Прочитать
const val = await komet.storage.get('counter'); // 42 или undefined

// Удалить
await komet.storage.remove('counter');

// Все ключи
const keys = await komet.storage.keys(); // ['counter', ...]
```

### komet.messages — перехват сообщений

Требует разрешения `interceptOutgoingMessages` / `interceptIncomingMessages`.

```js
// Перехват исходящих
komet.messages.onOutgoing(async (ctx) => {
  // ctx = { chatId, text, senderId, direction }
  if (ctx.text.includes('секрет')) {
    return { action: 'block' };           // заблокировать
  }
  return {
    action: 'replace',
    text: ctx.text.toUpperCase(),         // заменить текст
  };
  // return { action: 'passthrough' };    // пропустить без изменений
});

// Перехват входящих
komet.messages.onIncoming(async (ctx) => {
  return { action: 'passthrough' };
});
```

Возможные значения `action`:

| Значение      | Описание                              |
|---------------|---------------------------------------|
| `passthrough` | Пропустить без изменений (по умолчанию) |
| `replace`     | Заменить текст (поле `text`)          |
| `block`       | Заблокировать отправку/отображение    |

### komet.chatMenu — пункты меню чата

Требует разрешения `addChatMenuItems`.

```js
await komet.chatMenu.addItem('my_action', 'Моё действие', 'star');

komet.on('chatMenu.my_action', async ({ chatId }) => {
  komet.log('Нажали в чате', chatId);
});
```

### komet.chats — список чатов

Требует разрешения `readChats`.

```js
const chats = await komet.chats.list();
// [{ id, title, type, lastMessagePreview, unread }, ...]

const messages = await komet.chats.getMessages(chatId, 20);
// [{ id, text, senderId, timestamp }, ...]
```

### komet.profile — текущий пользователь

Требует разрешения `readSelfProfile`.

```js
const me = await komet.profile.getSelf();
// { id, name, phone }
```

### komet.notify(title, body)

Показывает локальное уведомление.

```js
komet.notify('Плагин', 'Привет из script.js!');
```

### komet.on / komet.off — события

```js
// Подписаться на события из Dart (например, onNewMessage из хоста)
komet.on('newMessage', (data) => {
  komet.log('Новое сообщение:', data.text);
});

// Отписаться
const handler = (data) => {};
komet.on('someEvent', handler);
komet.off('someEvent', handler);
```

---

## 3. Структура .kometplugin

`.kometplugin` — это обычный ZIP-архив. Обязательный файл: `manifest.json`.

```
my-plugin.kometplugin
├── manifest.json       ← обязательно
├── script.js           ← JS-логика (опционально)
├── icon.png            ← иконка 256×256 (опционально)
└── assets/             ← дополнительные файлы (опционально)
```

### manifest.json — полная схема

```jsonc
{
  "id": "com.example.myplugin",        // уникальный ID в стиле reverse-domain
  "name": "Мой плагин",
  "version": "1.0.0",
  "description": "Описание плагина",
  "author": "Автор",

  // Разрешения, которые плагин запрашивает у пользователя
  "permissions": [
    "interceptOutgoingMessages",
    "interceptIncomingMessages",
    "readChats",
    "addChatMenuItems"
  ],

  // Переопределение констант приложения
  "overrideConstants": {
    "primaryColor": "#FF6B35",
    "messageBubbleRadius": 18,
    "animationSpeed": 1.5
  },

  // Дополнительные разделы в Settings → Плагины
  "settingsSections": [
    {
      "id": "my_section",
      "title": "Мои настройки",
      "icon": "tune",
      "items": [
        {
          "type": "toggle",
          "id": "enable_feature",
          "title": "Включить фичу",
          "subtitle": "Описание фичи",
          "key": "my_feature_enabled",
          "defaultValue": false
        },
        {
          "type": "slider",
          "id": "speed_slider",
          "title": "Скорость",
          "key": "my_speed",
          "min": 0.5,
          "max": 3.0,
          "divisions": 10,
          "defaultValue": 1.0
        },
        {
          "type": "button",
          "title": "Открыть сайт",
          "icon": "open_in_browser",
          "action": {
            "type": "openUrl",
            "target": "https://example.com"
          }
        }
      ]
    }
  ],

  // Вставка подраздела в существующий раздел настроек
  "settingsSubsections": [
    {
      "id": "my_sub",
      "parentSection": "NotificationsScreen",
      "title": "Фильтр уведомлений",
      "items": []
    }
  ],

  // Замена стандартных экранов
  "replaceScreens": {
    "AboutScreen": {
      "title": "О нас",
      "widgets": [
        {
          "type": "text",
          "properties": { "text": "Моя версия About", "style": "headlineSmall" }
        }
      ]
    }
  }
}
```

### Доступные типы элементов

| Тип          | Описание                                          |
|--------------|---------------------------------------------------|
| `button`     | Кнопка с действием                               |
| `toggle`     | Переключатель (boolean)                           |
| `slider`     | Ползунок (double, min–max)                       |
| `text`       | Текстовая метка                                   |
| `divider`    | Разделитель                                       |
| `navigation` | Пункт-навигация (переход в подраздел)             |

### Типы действий (`action`)

| Тип           | target                    | value                |
|---------------|---------------------------|----------------------|
| `setValue`    | ключ в plugin_values      | новое значение       |
| `callAction`  | `clear_cache` / `reconnect` / `show_snackbar` | — |
| `openUrl`     | URL                       | —                    |
| `navigate`    | screen ID                 | —                    |

---

## 4. Пример плагина

Плагин, который зачёркивает каждое 5-е исходящее сообщение.

**manifest.json**
```json
{
  "id": "com.example.strikethrough",
  "name": "Зачёркиватель",
  "version": "1.0.0",
  "description": "Каждое 5-е сообщение автоматически зачёркивается",
  "author": "Example",
  "permissions": ["interceptOutgoingMessages"]
}
```

**script.js**
```js
let counter = 0;

(async () => {
  const saved = await komet.storage.get('counter');
  counter = saved ?? 0;
  komet.log('Зачёркиватель запущен, счётчик:', counter);
})();

komet.messages.onOutgoing(async (ctx) => {
  counter++;
  await komet.storage.set('counter', counter);

  if (counter % 5 === 0) {
    komet.log('Зачёркиваем сообщение #' + counter);
    return {
      action: 'replace',
      text: '~~' + ctx.text + '~~',
    };
  }

  return { action: 'passthrough' };
});
```

---

## 5. Bluetooth Mesh P2P

Komet поддерживает офлайн-общение через Bluetooth mesh-сеть — без интернета
и без сервера.

### Как это работает

```
Устройство A ──BT──► Устройство B ──BT──► Устройство C
                         │
                         └──BT──► Устройство D
```

- Каждое устройство автоматически ищет соседей через Bluetooth Discovery.
- Сообщения содержат **TTL (time-to-live)** — максимальное количество хопов.
- Уже виденные сообщения **дедуплицируются** по уникальному ID.
- Поддерживаются **broadcast** (всем) и **unicast** (конкретному устройству).

### Запуск

Настройки → Mesh-чат (или кнопка в главном экране).

Или программно из Dart:

```dart
final mesh = BluetoothMeshTransport();

final result = await mesh.start(displayName: 'Мой ник');
if (result == MeshStartResult.ok) {
  // Слушаем входящие
  mesh.incoming.listen((msg) {
    print('${msg.senderName}: ${msg.text}');
  });

  // Отправить broadcast
  await mesh.send(text: 'Привет всем!', senderName: 'Мой ник');

  // Отправить конкретному устройству
  await mesh.send(
    text: 'Личное сообщение',
    senderName: 'Мой ник',
    targetId: 'AA:BB:CC:DD:EE:FF',
  );
}
```

### Модель сообщения (`MeshMessage`)

| Поле          | Тип      | Описание                                    |
|---------------|----------|---------------------------------------------|
| `id`          | String   | Уникальный hex-ID (128 бит random)          |
| `originId`    | String   | MAC-адрес отправителя                       |
| `targetId`    | String   | MAC адресата или `*` для broadcast          |
| `text`        | String   | Текст сообщения                             |
| `senderName`  | String   | Отображаемое имя                            |
| `timestamp`   | int      | Unix milliseconds UTC                       |
| `ttl`         | int      | Оставшихся хопов (начальное: 5)             |
| `isRelayed`   | bool     | Пришло ли через промежуточный узел          |

### Требования и разрешения (Android)

В `AndroidManifest.xml` уже прописаны:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

> На Android 12+ приложение запрашивает `BLUETOOTH_CONNECT` и `BLUETOOTH_SCAN`
> через runtime permissions при первом запуске mesh.

### Протокол передачи

Данные передаются по Bluetooth SPP (Serial Port Profile, UUID `00001101-...`).
Формат фрейма: `<JSON>\n` — каждый объект сообщения в одну строку, завершённую
символом newline (`0x0A`). Это позволяет легко читать сообщения потоково.

### Ограничения

- **Android only** в текущей реализации (через `flutter_bluetooth_serial`).
- Дальность Bluetooth ~10–30 м; mesh расширяет покрытие через ретрансляцию.
- Bluetooth Classic (не BLE) — более высокая пропускная способность, но
  требует явного pairing на некоторых устройствах.
- iOS: CoreBluetooth BLE поддержка планируется в следующих версиях.

---

## 6. Разрешения плагинов

| Разрешение                  | Описание                                       | Чувствительное |
|-----------------------------|------------------------------------------------|:--------------:|
| `readChats`                 | Список чатов (названия, типы, превью)          |                |
| `readMessages`              | История сообщений                              | ✓              |
| `readContacts`              | Список контактов                               | ✓              |
| `readSelfProfile`           | Данные вашего аккаунта                         | ✓              |
| `receiveMessageEvents`      | Уведомления о новых сообщениях в реальном времени | ✓           |
| `receiveChatEvents`         | Уведомления об изменениях чатов                |                |
| `overrideConstants`         | Изменение внутренних параметров приложения     |                |
| `replaceScreens`            | Замена стандартных экранов                     |                |
| `addSettingsSections`       | Добавление разделов в настройки                |                |
| `interceptOutgoingMessages` | Читать и изменять ваши сообщения перед отправкой | ✓            |
| `interceptIncomingMessages` | Читать и изменять входящие сообщения           | ✓              |
| `addChatMenuItems`          | Добавлять кнопки в меню ⋮ чата                 |                |

Разрешения из `manifest.json → permissions` запрашиваются при установке, но
**не выдаются автоматически** — пользователь сам включает их в
Настройки → Плагины → [плагин] → Разрешения.

---

## Изменения в этой версии

### JS-движок для плагинов

**Файл:** `lib/plugins/plugin_js_engine.dart`

До этого `scriptPath` сохранялся в модели, но скрипт нигде не выполнялся.
Теперь:

- При включении плагина со `script.js` запускается изолированный **headless
  WebView** (`flutter_inappwebview`).
- Скрипт получает объект `komet` с полным API (хранилище, перехват сообщений,
  уведомления, список чатов).
- Вызовы между JS и Dart выполняются через `JavaScriptHandler` и промисы.
- При выключении или удалении плагина WebView уничтожается.

### Bluetooth Mesh P2P

**Файлы:**
- `lib/mesh/bluetooth_mesh_transport.dart` — транспортный слой
- `lib/screens/mesh_chat_screen.dart` — UI

Новый способ общения без интернета: устройства формируют Bluetooth-сеть и
ретранслируют сообщения друг через друга (store-and-forward mesh с TTL).

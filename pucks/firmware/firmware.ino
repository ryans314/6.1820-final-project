#include <WiFiNINA.h>
#include <ArduinoJson.h>
#include <Adafruit_NeoPixel.h>
#include "secrets.h"

const int   SERVER_PORT = 8000;
const char* PUCK_ID     = "puck_1";
IPAddress   SERVER_IP(SECRET_SERVER_HOST);

#define NEOPIXEL_PIN   5
#define NEOPIXEL_COUNT 16

WiFiClient client;
Adafruit_NeoPixel ring(NEOPIXEL_COUNT, NEOPIXEL_PIN, NEO_GRB + NEO_KHZ800);
bool wsConnected = false;



uint32_t colorFromName(const char* name) {
    if (strcmp(name, "red")    == 0) return ring.Color(255,   0,   0);
    if (strcmp(name, "green")  == 0) return ring.Color(  0, 180,   0);
    if (strcmp(name, "blue")   == 0) return ring.Color(  0,   0, 255);
    if (strcmp(name, "purple") == 0) return ring.Color(180,   0, 255);
    if (strcmp(name, "white")  == 0) return ring.Color(255, 180, 100);
    if (strcmp(name, "yellow") == 0) return ring.Color(255, 255,   0);
    if (strcmp(name, "brown")  == 0) return ring.Color( 80,  40,   0);
    if (strcmp(name, "orange") == 0) return ring.Color(255, 120,   0);
    if (strcmp(name, "pink")   == 0) return ring.Color(255,  80, 120);
    if (strcmp(name, "cyan")   == 0) return ring.Color(  0, 255, 180);
    if (strcmp(name, "off")    == 0) return ring.Color(  0,   0,   0);
    return ring.Color(255, 180, 100);
}

void setColor(uint32_t color) {
    ring.fill(color);
    ring.show();
}

void wheelTransition(uint32_t targetColor) {
    for (int i = 0; i < NEOPIXEL_COUNT; i++) {
        ring.setPixelColor(i, targetColor);
        ring.show();
        delay(8);
    }
}

// --- Incoming message handler ---

void handleMessage(const String& text) {
    StaticJsonDocument<256> doc;
    if (deserializeJson(doc, text) != DeserializationError::Ok) return;

    const char* action = doc["action"];
    if (!action) return;

    if (strcmp(action, "change_color") == 0) {
        const char* color = doc["color"] | "white";
        wheelTransition(colorFromName(color));
        Serial.print("Color: ");
        Serial.println(color);
    } else if (strcmp(action, "flash") == 0) {
        // Brief white flash to confirm tap, then restore previous color
        uint32_t prev = ring.getPixelColor(0);
        setColor(ring.Color(255, 255, 255));
        delay(80);
        setColor(prev);
    }
}

// --- WebSocket TX (client→server frames must be masked) ---

static const uint8_t WS_MASK[4] = {0x12, 0x34, 0x56, 0x78};

void wsSend(const String& text) {
    size_t len = text.length();
    client.write((uint8_t)0x81);
    if (len <= 125) {
        client.write((uint8_t)(0x80 | len));
    } else {
        client.write((uint8_t)0xFE);
        client.write((uint8_t)((len >> 8) & 0xFF));
        client.write((uint8_t)(len & 0xFF));
    }
    client.write(WS_MASK, 4);
    for (size_t i = 0; i < len; i++) {
        client.write((uint8_t)(text[i] ^ WS_MASK[i % 4]));
    }
}

// --- WebSocket RX ---

void wsReadFrame() {
    if (client.available() < 2) return;

    uint8_t b0 = client.read();
    uint8_t b1 = client.read();
    uint8_t  opcode     = b0 & 0x0F;
    bool     masked     = b1 & 0x80;
    uint16_t payloadLen = b1 & 0x7F;

    if (payloadLen == 126) {
        uint8_t ext[2];
        client.readBytes(ext, 2);
        payloadLen = ((uint16_t)ext[0] << 8) | ext[1];
    }

    uint8_t maskKey[4] = {};
    if (masked) client.readBytes(maskKey, 4);

    String payload = "";
    for (uint16_t i = 0; i < payloadLen; i++) {
        unsigned long t = millis();
        while (!client.available() && millis() - t < 1000) delay(1);
        if (!client.available()) { wsConnected = false; return; }
        uint8_t c = client.read();
        payload += (char)(masked ? (c ^ maskKey[i % 4]) : c);
    }

    if (opcode == 0x8) {        // Close
        wsConnected = false;
    } else if (opcode == 0x9) { // Ping → Pong
        client.write((uint8_t)0x8A);
        client.write((uint8_t)0x80);
        client.write((uint8_t)0x00); client.write((uint8_t)0x00);
        client.write((uint8_t)0x00); client.write((uint8_t)0x00);
    } else if (opcode == 0x1) { // Text
        handleMessage(payload);
    }
}

// --- WiFi ---

void scanWifi() {
    Serial.println("Scanning networks...");
    int n = WiFi.scanNetworks();
    for (int i = 0; i < n; i++) {
        Serial.print("  ");
        Serial.print(WiFi.SSID(i));
        Serial.print("  RSSI:");
        Serial.print(WiFi.RSSI(i));
        Serial.print("  CH:");
        Serial.println(WiFi.channel(i));
    }
}

void connectWifi() {
    //scanWifi();
    Serial.print("Connecting to WiFi");
    WiFi.begin(SECRET_WIFI_SSID, SECRET_WIFI_PASSWORD);
    unsigned long timeout = millis() + 20000;
    while (WiFi.status() != WL_CONNECTED && millis() < timeout) {
        delay(500);
        Serial.print(".");
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.print(" connected, puck IP: ");
        Serial.println(WiFi.localIP());
        Serial.print("WiFiNINA firmware: ");
        Serial.println(WiFi.firmwareVersion());
        delay(500); // let TCP stack settle
    } else {
        Serial.println(" timed out");
    }
}

bool connectWebSocket() {
    if (WiFi.status() != WL_CONNECTED) return false;

    Serial.print("TCP connecting to ");
    Serial.print(SERVER_IP);
    Serial.print(":");
    Serial.println(SERVER_PORT);
    int tcpResult = 0;
    for (int i = 0; i < 3; i++) {
        tcpResult = client.connect(SERVER_IP, SERVER_PORT);
        if (tcpResult) break;
        Serial.print("TCP attempt ");
        Serial.print(i + 1);
        Serial.println(" failed, retrying...");
        delay(500);
    }
    if (!tcpResult) {
        Serial.println("TCP connect failed after 3 attempts");
        return false;
    }

    String path = String("/ws/puck/") + PUCK_ID;
    client.print(String("GET ") + path + " HTTP/1.1\r\n");
    client.print(String("Host: ") + SERVER_IP.toString() + "\r\n");
    client.print("Upgrade: websocket\r\n");
    client.print("Connection: Upgrade\r\n");
    client.print("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n");
    client.print("Sec-WebSocket-Version: 13\r\n");
    client.print("\r\n");

    unsigned long timeout = millis() + 3000;
    String response = "";
    while (millis() < timeout) {
        while (client.available()) response += (char)client.read();
        if (response.indexOf("\r\n\r\n") >= 0) break;
        delay(10);
    }

    if (response.indexOf("101") < 0) {
        Serial.println("Handshake failed");
        client.stop();
        return false;
    }

    StaticJsonDocument<128> doc;
    doc["type"]      = "identify";
    doc["player_id"] = PUCK_ID;
    doc["username"]  = PUCK_ID;
    String out;
    serializeJson(doc, out);
    wsSend(out);

    wsConnected = true;
    Serial.println("WebSocket connected");
    return true;
}

// --- Arduino lifecycle ---

void setup() {
    Serial.begin(115200);

    ring.begin();
    ring.setBrightness(80);
    setColor(ring.Color(0, 0, 0));

    connectWifi();
    connectWebSocket();

    if (wsConnected) {
        setColor(ring.Color(255, 255, 255)); //flash white to show it is connected
        delay(300);
        setColor(ring.Color(0, 0, 0));
    } else {
        setColor(ring.Color(30, 0, 0));
    }
}

void loop() {
    if (WiFi.status() != WL_CONNECTED) {
        wsConnected = false;
        client.stop();
        connectWifi();
        return;
    }

    if (!client.connected() || !wsConnected) {
        client.stop();
        delay(2000);
        connectWebSocket();
        return;
    }

    wsReadFrame();
}

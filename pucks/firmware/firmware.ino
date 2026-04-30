#include <WiFiNINA.h>
#include <ArduinoWebsockets.h>
#include <ArduinoJson.h>
#include <Adafruit_NeoPixel.h>

// --- Config (edit per puck) ---
const char* WIFI_SSID     = "YOUR_SSID";
const char* WIFI_PASSWORD = "YOUR_PASSWORD";
const char* SERVER_HOST   = "192.168.1.100";  // server LAN IP
const int   SERVER_PORT   = 8000;
const char* PUCK_ID       = "puck_1";         // unique per puck: puck_1, puck_2, puck_3

#define NEOPIXEL_PIN   6
#define NEOPIXEL_COUNT 16

// --- Globals ---
using namespace websockets;
WebsocketsClient ws;
Adafruit_NeoPixel ring(NEOPIXEL_COUNT, NEOPIXEL_PIN, NEO_GRB + NEO_KHZ800);

// Map the color names the server sends to RGB values
uint32_t colorFromName(const char* name) {
    if (strcmp(name, "red")    == 0) return ring.Color(255,   0,   0);
    if (strcmp(name, "green")  == 0) return ring.Color(  0, 255,   0);
    if (strcmp(name, "blue")   == 0) return ring.Color(  0,   0, 255);
    if (strcmp(name, "purple") == 0) return ring.Color(128,   0, 128);
    if (strcmp(name, "white")  == 0) return ring.Color(255, 255, 255);
    if (strcmp(name, "yellow") == 0) return ring.Color(255, 200,   0);
    if (strcmp(name, "brown")  == 0) return ring.Color(139,  69,  19);
    if (strcmp(name, "off")    == 0) return ring.Color(  0,   0,   0);
    return ring.Color(255, 255, 255);
}

void setColor(uint32_t color) {
    ring.fill(color);
    ring.show();
}

void onMessage(WebsocketsMessage msg) {
    StaticJsonDocument<256> doc;
    if (deserializeJson(doc, msg.data()) != DeserializationError::Ok) return;

    const char* action = doc["action"];
    if (!action) return;

    if (strcmp(action, "change_color") == 0) {
        const char* color = doc["color"] | "white";
        setColor(colorFromName(color));
        Serial.print("Color set to: ");
        Serial.println(color);
    }
}

void connectWifi() {
    Serial.print("Connecting to WiFi");
    while (WiFi.begin(WIFI_SSID, WIFI_PASSWORD) != WL_CONNECTED) {
        delay(1000);
        Serial.print(".");
    }
    Serial.println(" connected");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
}

void sendIdentify() {
    StaticJsonDocument<128> doc;
    doc["type"]      = "identify";
    doc["player_id"] = PUCK_ID;
    doc["username"]  = PUCK_ID;
    String out;
    serializeJson(doc, out);
    ws.send(out);
    Serial.println("Sent identify");
}

void connectWebSocket() {
    String path = String("/ws/puck/") + PUCK_ID;
    Serial.print("Connecting to WebSocket at ");
    Serial.println(path);

    ws.onMessage(onMessage);

    while (!ws.connect(SERVER_HOST, SERVER_PORT, path.c_str())) {
        Serial.println("WebSocket connect failed, retrying in 2s...");
        setColor(ring.Color(30, 0, 0));  // dim red = no server
        delay(2000);
    }

    sendIdentify();
    setColor(ring.Color(0, 0, 0));  // off = idle / waiting for game start
    Serial.println("WebSocket connected");
}

void setup() {
    Serial.begin(115200);

    ring.begin();
    ring.setBrightness(80);
    setColor(ring.Color(0, 0, 0));

    connectWifi();
    connectWebSocket();

    // Boot confirmation: brief white flash
    setColor(ring.Color(255, 255, 255));
    delay(300);
    setColor(ring.Color(0, 0, 0));
}

void loop() {
    if (!ws.available()) {
        Serial.println("WebSocket lost, reconnecting...");
        setColor(ring.Color(30, 0, 0));  // dim red = disconnected
        delay(1000);
        connectWebSocket();
        return;
    }
    ws.poll();
}

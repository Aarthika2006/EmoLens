
#include "esp_camera.h"
#include <WiFi.h>

// =====================================
// ESP32-CAM + RHYX M21-45 (GC2145)
// =====================================

#define CAMERA_MODEL_AI_THINKER

#include "camera_pins.h"

// WiFi credentials
const char* ssid = "12345678";
const char* password = "12345678";

// Camera web server function
void startCameraServer();

// =====================================
// SETUP
// =====================================

void setup() {

  Serial.begin(115200);
  Serial.setDebugOutput(true);
  Serial.println();

  Serial.println("================================");
  Serial.println(" RHYX M21-45 CAMERA STARTING");
  Serial.println("================================");

  // Camera configuration
  camera_config_t config = {};

  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;

  // Camera data pins
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;

  // Camera control pins
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;

  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;

  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;

  // Clock
  config.xclk_freq_hz = 20000000;

  // Camera settings
  config.pixel_format = PIXFORMAT_RGB565;
  config.frame_size = FRAMESIZE_QVGA;
  config.jpeg_quality = 12;

  config.fb_count = 1;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;

  Serial.println("Resolution: 320 x 240");
  Serial.println("Format: RGB565");

  Serial.printf("PSRAM: %s\n",
                psramFound() ? "Available" : "Not found");

  // =====================================
  // INITIALIZE CAMERA
  // =====================================

  Serial.println("Initializing camera...");

  esp_err_t err = esp_camera_init(&config);

  if (err != ESP_OK) {

    Serial.printf("Camera initialization failed: 0x%x\n", err);

    return;
  }

  Serial.println("Camera initialized successfully!");

  // Sensor information
  sensor_t *s = esp_camera_sensor_get();

  if (s != NULL) {
    Serial.printf("Camera PID: 0x%04X\n", s->id.PID);
  }

  // =====================================
  // CONNECT WIFI
  // =====================================

  Serial.println("Connecting to WiFi...");

  WiFi.begin(ssid, password);
  WiFi.setSleep(false);

  int attempts = 0;

  while (WiFi.status() != WL_CONNECTED && attempts < 40) {

    delay(500);
    Serial.print(".");

    attempts++;
  }

  if (WiFi.status() != WL_CONNECTED) {

    Serial.println("\nWiFi connection failed!");

    return;
  }

  Serial.println("\nWiFi connected!");

  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  // =====================================
  // START CAMERA WEB SERVER
  // =====================================

  Serial.println("Starting camera web server...");

  startCameraServer();

  Serial.println("Camera web server started!");

  Serial.print("Open this address: http://");
  Serial.println(WiFi.localIP());
}

// =====================================
// LOOP
// =====================================

void loop() {

  delay(10000);

}

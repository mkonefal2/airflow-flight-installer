#!/bin/bash

# Airflow setup script on Ubuntu VM from ZIP archive

# Variables
USER="airflow"
ZIP_FILE="epwa-flight-etl-main.zip"
EXTRACTED_DIR="epwa-flight-etl-main"
INSTALL_DIR="/home/$USER/epwa-flight-etl"
AIRFLOW_HOME="$INSTALL_DIR/airflow"
VENV_DIR="$INSTALL_DIR/venv"
PYTHON_VERSION="python3.10"

echo "[1/10] Updating system and installing dependencies..."
sudo apt update
sudo apt install -y python3-pip python3-venv unzip openjdk-17-jdk

# Set JAVA_HOME path
JAVA_PATH=$(dirname $(dirname $(readlink -f $(which javac))))
echo "JAVA_HOME will be set to: $JAVA_PATH"

echo "[2/10] Creating airflow user if not present..."
if ! id -u "$USER" > /dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$USER"
fi

echo "[3/10] Cleaning old installation..."
sudo systemctl stop airflow-webserver 2>/dev/null
sudo systemctl stop airflow-scheduler 2>/dev/null
sudo systemctl disable airflow-webserver 2>/dev/null
sudo systemctl disable airflow-scheduler 2>/dev/null
sudo rm -f /etc/systemd/system/airflow-webserver.service
sudo rm -f /etc/systemd/system/airflow-scheduler.service
sudo rm -rf "$INSTALL_DIR"

echo "[4/10] Extracting ZIP archive..."
if [[ ! -f "$ZIP_FILE" ]]; then
  echo "❌ ZIP file $ZIP_FILE not found. Please place it in the same directory."
  exit 1
fi

unzip -q "$ZIP_FILE"
mv "$EXTRACTED_DIR" "$INSTALL_DIR"
sudo chown -R "$USER:$USER" "$INSTALL_DIR"

echo "[4.1/10] Creating .env file for API key..."
read -p "🔑 Enter your AviationStack API key: " API_KEY
ENV_FILE="$INSTALL_DIR/.env"
sudo -u "$USER" tee "$ENV_FILE" > /dev/null <<EOF
AVIATIONSTACK_API_KEY=$API_KEY
EOF
echo "✅ .env file created at $ENV_FILE"

echo "[5/10] Setting environment variable AIRFLOW_HOME..."
echo "export AIRFLOW_HOME=$AIRFLOW_HOME" | sudo tee /etc/profile.d/airflow.sh
echo "export JAVA_HOME=$JAVA_PATH" | sudo tee /etc/profile.d/java.sh
source /etc/profile.d/airflow.sh
source /etc/profile.d/java.sh

echo "[6/10] Creating Airflow directories..."
sudo -u "$USER" mkdir -p "$AIRFLOW_HOME"/{dags,logs,plugins}
sudo -u "$USER" mkdir -p "$INSTALL_DIR/db"

echo "[7/10] Creating and activating virtual environment..."
sudo -u "$USER" $PYTHON_VERSION -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "[8/10] Installing Python dependencies..."
pip install --upgrade pip setuptools wheel
pip install -r "$INSTALL_DIR/requirements.txt"

echo "[9/10] Initializing Airflow..."
airflow db migrate
airflow users create \
  --username admin \
  --firstname Airflow \
  --lastname Admin \
  --role Admin \
  --email airflow_admin@example.com \
  --password 'StrongPassword123'

echo "🔧 Fixing permissions..."
sudo chown -R "$USER:$USER" "/home/$USER"

echo "[10/10] Creating Airflow systemd services..."

sudo tee /etc/systemd/system/airflow-webserver.service > /dev/null <<EOF
[Unit]
Description=Airflow webserver daemon
After=network.target

[Service]
User=$USER
Group=$USER
Environment="AIRFLOW_HOME=$AIRFLOW_HOME"
Environment="PATH=$VENV_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
Environment="JAVA_HOME=$JAVA_PATH"
ExecStart=$VENV_DIR/bin/airflow webserver --port 8080 --host 0.0.0.0
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/airflow-scheduler.service > /dev/null <<EOF
[Unit]
Description=Airflow scheduler daemon
After=network.target

[Service]
User=$USER
Group=$USER
Environment="AIRFLOW_HOME=$AIRFLOW_HOME"
Environment="PATH=$VENV_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
Environment="JAVA_HOME=$JAVA_PATH"
ExecStart=$VENV_DIR/bin/airflow scheduler
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 Starting Airflow services..."
sudo systemctl daemon-reload
sudo systemctl enable airflow-webserver
sudo systemctl enable airflow-scheduler
sudo systemctl start airflow-webserver
sudo systemctl start airflow-scheduler

sleep 5

WEB_STATUS=$(systemctl is-active airflow-webserver)
SCHEDULER_STATUS=$(systemctl is-active airflow-scheduler)

if [[ "$WEB_STATUS" == "active" && "$SCHEDULER_STATUS" == "active" ]]; then
  IP=$(hostname -I | awk '{print $1}')
  echo "✅ Airflow is running at: http://$IP:8080"
else
  echo "❌ Something went wrong. Check the services:"
  SYSTEMD_PAGER=cat sudo systemctl --no-pager status airflow-webserver
  SYSTEMD_PAGER=cat sudo systemctl --no-pager status airflow-scheduler
fi

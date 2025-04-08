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

# Display installation phase
echo "[1/9] Updating system and installing dependencies..."
sudo apt update
sudo apt install -y python3-pip python3-venv unzip

# Create airflow user if not exists
echo "[2/9] Creating airflow user if not present..."
if ! id -u "$USER" > /dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$USER"
fi

# Remove previous installation if exists
echo "[3/9] Removing previous installation if it exists..."
sudo systemctl stop airflow-webserver 2>/dev/null
sudo systemctl stop airflow-scheduler 2>/dev/null
sudo systemctl disable airflow-webserver 2>/dev/null
sudo systemctl disable airflow-scheduler 2>/dev/null
sudo rm -f /etc/systemd/system/airflow-webserver.service
sudo rm -f /etc/systemd/system/airflow-scheduler.service
sudo rm -rf "$INSTALL_DIR"

# Check if the ZIP file exists
echo "[4/9] Extracting the ZIP project archive..."
if [[ ! -f "$ZIP_FILE" ]]; then
  echo "❌ ZIP file $ZIP_FILE not found. Please place it in the same directory."
  exit 1
fi

unzip -q "$ZIP_FILE"
mv "$EXTRACTED_DIR" "$INSTALL_DIR"
sudo chown -R "$USER:$USER" "$INSTALL_DIR"

# Set AIRFLOW_HOME globally
echo "[5/9] Setting environment variable AIRFLOW_HOME..."
echo "export AIRFLOW_HOME=$AIRFLOW_HOME" | sudo tee /etc/profile.d/airflow.sh
source /etc/profile.d/airflow.sh

# Create Airflow directories
echo "[6/9] Creating Airflow directories..."
sudo -u "$USER" mkdir -p "$AIRFLOW_HOME"/{dags,logs,plugins}

# Create and activate virtual environment
echo "[7/9] Creating and activating virtual environment..."
sudo -u "$USER" $PYTHON_VERSION -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Install requirements
echo "[8/9] Installing Python packages from requirements.txt..."
if ! pip install --upgrade pip setuptools wheel; then
  echo "❌ Failed to upgrade pip/setuptools/wheel."
  exit 1
fi

if ! pip install -r "$INSTALL_DIR/requirements.txt"; then
  echo "❌ Failed to install requirements. Check requirements.txt for conflicts."
  exit 1
fi

# Initialize Airflow database
airflow db migrate || { echo "❌ Failed to initialize the Airflow DB."; exit 1; }

# Create Airflow admin user
airflow users create \
  --username admin \
  --firstname Airflow \
  --lastname Admin \
  --role Admin \
  --email airflow_admin@example.com \
  --password 'StrongPassword123' || { echo "❌ Failed to create Airflow admin user."; exit 1; }

# Set permissions
sudo chown -R "$USER:$USER" "/home/$USER"

# Create systemd services
sudo tee /etc/systemd/system/airflow-webserver.service > /dev/null <<EOF
[Unit]
Description=Airflow webserver daemon
After=network.target

[Service]
User=$USER
Group=$USER
Environment="AIRFLOW_HOME=$AIRFLOW_HOME"
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
ExecStart=$VENV_DIR/bin/airflow scheduler
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Start and enable services
echo "🔄 Starting Airflow services..."
sudo systemctl daemon-reload
sudo systemctl enable airflow-webserver
sudo systemctl enable airflow-scheduler
sudo systemctl start airflow-webserver
sudo systemctl start airflow-scheduler

# Wait for services to initialize
sleep 5

# Check service status
WEB_STATUS=$(systemctl is-active airflow-webserver)
SCHEDULER_STATUS=$(systemctl is-active airflow-scheduler)

if [[ "$WEB_STATUS" == "active" && "$SCHEDULER_STATUS" == "active" ]]; then
  IP=$(hostname -I | awk '{print $1}')
  echo "✅ Installation completed successfully. Airflow is available at: http://$IP:8080"
else
  echo "❌ Installation failed. Check the status of the services below:"
  SYSTEMD_PAGER=cat sudo systemctl --no-pager status airflow-webserver
  SYSTEMD_PAGER=cat sudo systemctl --no-pager status airflow-scheduler
fi

# Building a Custom Rust Honeypot and Deploying It on Oracle Cloud for Free

Looking for a fun and educational hands-on project that combines Rust coding with cloud deployment? In this guide, we will build a simple honeypot—a minimal TCP server in Rust that listens on a specific port and logs every incoming request—then deploy it to an Ubuntu instance on Oracle Cloud Infrastructure (OCI) for FREE. A honeypot offers a fascinating window into the malicious scans and attacks traveling the internet while also providing a playful way to practice coding, cross-compiling, and network configuration. By following these steps, you will gain valuable Rust experience, learn how to set up OCI for external traffic, and come away with deeper insight into real-world attack patterns.

- Note 1: I am using a Apple M1 Pro MacBook for development and cross-compiling for x86_64 architecture.

---

# 1. Prerequisites
Welcome to the warm-up lap before our Rust honeypot grand adventure! Here’s what you need to get started:

## 1.1 Oracle Cloud Account
First things first: snag an [Oracle Cloud account](https://www.oracle.com/cloud/free/) (free is our favorite price). The Always Free tier is pretty sweet since it gives you a no-cost VM to play around with. Perfect for deploying a honeypot without emptying your wallet.

- Note 1: you can of course use any cloud provider or your own server for this project. But Oracle Cloud offers an "Always Free" tier that allows you to run a small VM at no cost and I was looking for an excuse to try it out. Initially I was interested in the ARM architecture but those are limited in my region of choice so I am using a AMD64 instance for this project.

## 1.2 Ubuntu VM in OCI
Go to the Oracle Cloud console and [spin up an Ubuntu instance](https://cloud.oracle.com/compute/instances). Make sure you’ve got your SSH key set up and can **actually get in**. Some additional information on how to use SSH can be found in the [Oracle Cloud documentation](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/accessinginstance.htm).

## 1.3 Rust Installed Locally
If you do not have Rust installed look here for the [basic setup steps](https://www.rust-lang.org/learn/get-started). To add another architecture Rust up your local environment with the following:

```bash
rustup update

# Add the target for x86_64 architecture
rustup target add x86_64-unknown-linux-gnu
```

Personally I am using **stable-aarch64-apple-darwin** on an Apple Silicon Mac for development and cross-compilation.
Because I wanted to cross-compile to `x86_64` the architecture of AMD64 (a usual suspect for cloud VMs), I installed this handy toolchain:

```bash
brew install messense/macos-cross-toolchains/x86_64-unknown-linux-gnu
```

If your setup is different, fear not—just make sure you have some way to compile your Rust code into a binary that your Ubuntu server recognizes.

## 1.4 Basic Terminal / SSH Skills

Brush up on your command line wizardry and SSH know-how. If you can SSH into your server, open files in your favorite terminal editor you’re set! If you are not there yet, no worries—there are plenty of tutorials out there to help you get up to speed, e.g. [here](https://www.pluralsight.com/resources/blog/cloud/ssh-and-scp-howto-tips-tricks).

---

# 2. Coding the Honeypot in Rust

## 2.1 Project Setup

To get started, we’ll create a fresh Rust project for our honeypot:

```bash
cargo new honeypot
```

This initializes a new folder named honeypot containing your basic Cargo scaffolding. For a minimal approach, we won’t require any external crates at this stage—plain Rust’s standard library has all we need for simple socket listening and logging. Below is an example Cargo.toml you might use:

```toml
[package]
name = "honeypot"
authors = ["Bob Peters <contact@rust-trends.com>"]
version = "0.1.0"
edition = "2021"

[dependencies]
```

That’s it, no dependencies listed because Rust’s standard library already includes the core networking (std::net) and concurrency (std::thread) features we need for this basic honeypot. Of course, if you decide to add extra functionality (like logging libraries, async runtimes, or protocol parsers), this is where you’d specify them under [dependencies].

Next, open `src/main.rs`, and you will find a bare-bones “Hello, world!” file. We will soon replace that with our honeypot logic.

## 2.2 Minimal TCP Server Code

Here’s a simple TCP server that listens on port 2222, for every connection a thread is spawned. Each thread logs incoming data to a file and stdout.

```rust
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

fn main() {
    let listener = TcpListener::bind("0.0.0.0:2222").expect("Could not bind to address");

    println!("Honeypot is Listening on port 2222");

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                thread::spawn(|| {
                    handle_client(stream);
                });
            }
            Err(e) => {
                eprintln!("Error: {}", e);
            }
        }
    }
}

fn handle_client(mut stream: TcpStream) {
    let peer_addr = match stream.peer_addr() {
        Ok(addr) => addr.to_string(),
        Err(_) => "Unknown".to_string(),
    };

    let mut buffer = [0; 1024];
    let now = get_epoch_time();

    println!("Received connection from {}", peer_addr);

    // Open a (new) file to log the request
    let filename = format!("/opt/honeypot/{}_{}.log", now, peer_addr);

    let mut file = std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(filename)
        .expect("Could not open file");

    loop {
        match stream.read(&mut buffer) {
            Ok(n) => {
                if n == 0 {
                    println!("Connection closed by {}", peer_addr);
                    break;
                }

                // Try if the request is a valid string
                // If it is a valid string, it will be printed
                // If it is binary data, it will be printed as a string
                let request = String::from_utf8_lossy(&buffer[..n]);
                println!("Received request from {}: {}", peer_addr, request);

                // Write the request to the file
                file.write_all(&buffer[..n])
                    .expect("Could not write to file");

                // Close the file
                file.sync_all().expect("Could not sync file");
            }
            Err(e) => {
                eprintln!("Error reading from {}: {}", peer_addr, e);
                break;
            }
        }
    }
}

fn get_epoch_time() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("Time went backwards")
        .as_secs()
}
```

### 2.2.1 Handling Connections
Each incoming connection is handled in a separate thread to avoid blocking the main loop. This way, the honeypot can handle multiple connections simultaneously. The `handle_client` function reads data from the incoming stream, logs it to a file, and prints it to the console. The `get_epoch_time` function generates a timestamp for the log file name.

The TcpListener is bound to `0.0.0.0:2222`, which means it listens on all available network interfaces on port 2222. This allows the honeypot to accept connections from any IP address. The `listener.incoming()` method returns an iterator over incoming connections (infinitely), which we loop over to handle each connection. Great job! You’ve set up your first TCP listener.

The TcpStream represents the connection to a client. We use `stream.peer_addr()` to get the IP address of the client. If the address is successfully retrieved, we convert it to a string; otherwise, we use "Unknown". We then create a buffer to read data from the stream and a file to log the incoming data.

### 2.2.2 Logging Data
The `handle_client` function reads data from the stream into the buffer and writes it to the log file. If the read operation returns 0 bytes, the connection is closed, and the function breaks out of the loop. We use `String::from_utf8_lossy` to convert the buffer to a string, handling invalid UTF-8 sequences gracefully. This allows us to log binary data like �, as well as text.

## 2.3 Enhancing the Honeypot
This can be extended in many ways, for example, you could add a banner to mimic a real service, or you could add a database to store the logs. Adding more ports, or even emulating a specific protocol. But for now, this is a good starting point.

---

# 3. Building and Packaging

## 3.1 Native vs. Cross-Compilation
Since we want to deploy our honeypot on an Ubuntu AMD64 server, we need to compile our Rust code for the x86_64 architecture. If your development machine has the same architecture, you can compile natively `cargo build --release`. Otherwise, you’ll need to cross-compile for the target architecture. It is one of the benefits of Rust that it is easy to cross-compile.

In my case, I am using an Apple M1 Pro MacBook, so I need to cross-compile for x86_64. Here’s how you can do it:

```bash
cargo build --release --target x86_64-unknown-linux-gnu
```

This creates a binary optimized for the x86_64 architecture, which you can then transfer to your Ubuntu server. It is located in `target/x86_64-unknown-linux-gnu/release/honeypot`.

Why not use the debug build? The debug build includes additional symbols and debugging information, making the binary larger and slower. The release build is optimized for performance and size, making it more suitable for deployment.

## 3.2 Testing Locally
Before deploying to Oracle Cloud, you can test your honeypot locally. Build it and run it with `cargo run --release` the binary on your development machine and connect to it using `telnet localhost 2222` or `nc localhost 2222`. You should see the connection logs in your terminal and a new log file created in the current directory.

---

# 4. Deploying to Oracle Cloud

## 4.1 Orcale Cloud Infrastructure Network Configuration
By default, Oracle Cloud blocks inbound traffic on custom ports. You need to create an **Ingress Rule** in the **Security List** or **Network Security Group** for your instance’s subnet. Example: Open port `2222` to `0.0.0.0/0` via TCP.

- Go to the Oracle Cloud console and navigate to your instance
- Open your instance’s **VNIC** details
- Click on the **Security Lists** or **Network Security Groups** link
- Add a new **Ingress Rule** to allow traffic on port `2222` from `0.0.0.0/0` this is not recommended for production, but for a honeypot it is fine. This notation is called CIDR and it means all IP addresses.
- Save the changes and wait for them to take effect.

Additional tip is to close the actual SSH port on 22 after you have deployed and tested the honeypot service, so that attackers aren’t attempting to brute-force your "real" SSH port.

## 4.2 Uploading the Honeypot Binary
To upload the binary to the server, you can use `scp` or a deployment script. I choose to use a deployment script to automate the process, because I will be doing this multiple times.

```bash
#!/usr/bin/env bash

##############################################################################
# Configuration
##############################################################################

# Path to your SSH private key
SSH_KEY="$HOME/.ssh/id_ssh_key" # Change this to your private key

# SSH username and server IP
SERVER_USER="ubuntu"
SERVER_HOST="xxx.xxx.xxx.xxx" # Change this to your server's IP

# Local paths
LOCAL_BINARY="./target/x86_64-unknown-linux-gnu/release/honeypot"                  # Compiled honeypot binary
LOCAL_INSTALL_SCRIPT="./install_honeypot_service.sh"

# Remote locations
REMOTE_DIR="/home/ubuntu"                  # Temporary location for uploads
REMOTE_BINARY_PATH="${REMOTE_DIR}/honeypot"
REMOTE_INSTALL_SCRIPT="${REMOTE_DIR}/install_honeypot_service.sh"

##############################################################################
# 0. Build the binary
##############################################################################

echo "=== Building the honeypot binary... ==="
cargo build --release --target x86_64-unknown-linux-gnu
if [ $? -ne 0 ]; then
  echo "Error: Failed to build the honeypot binary."
  exit 1
fi

##############################################################################
# 1. Upload the new binary
##############################################################################

echo "=== Uploading the honeypot binary to ${SERVER_USER}@${SERVER_HOST}... ==="
scp -i "${SSH_KEY}" "${LOCAL_BINARY}" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_BINARY_PATH}"
if [ $? -ne 0 ]; then
  echo "Error: Failed to upload the honeypot binary."
  exit 1
fi
echo "=== Successfully uploaded binary. ==="

##############################################################################
# 2. Upload the install script
##############################################################################

echo "=== Uploading install script to ${SERVER_USER}@${SERVER_HOST}... ==="
scp -i "${SSH_KEY}" "${LOCAL_INSTALL_SCRIPT}" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_INSTALL_SCRIPT}"
if [ $? -ne 0 ]; then
  echo "Error: Failed to upload install script."
  exit 1
fi
echo "=== Successfully uploaded install script. ==="

##############################################################################
# 3. Run install script remotely
##############################################################################

echo "=== Running install script on the remote server... ==="
ssh -i "${SSH_KEY}" "${SERVER_USER}@${SERVER_HOST}" << EOF
  set -e  # Exit on any command error

  # Make sure script is executable
  chmod +x "${REMOTE_INSTALL_SCRIPT}"

  # Run it with sudo privileges (prompts if needed)
  sudo "${REMOTE_INSTALL_SCRIPT}"

  # Done
EOF

if [ $? -eq 0 ]; then
  echo "=== Deployment successful! ==="
else
  echo "=== Deployment encountered an error. ==="
  exit 1
fi
```

This script automates the process of building the binary, uploading it to the server, and running an installation script. You can customize it to fit your needs.

## 4.3 Installation Script
Create an installation script to set up the honeypot on the server. Here’s an example script that installs the honeypot as a systemd service. It’s idempotent, meaning you can run it multiple times without causing issues.

```bash
#!/usr/bin/env bash
#
# install_honeypot_service.sh
#
# Idempotent script to install/upgrade the 'honeypot' systemd service.
# Safe to run multiple times.
#
# Steps:
# 1. Create 'honeypot' user if missing
# 2. Create /opt/honeypot dir if missing
# 3. Copy local binary to /opt/honeypot if it differs
# 4. Create or update systemd unit file
# 5. Reload & restart service

set -euo pipefail

###############################################################################
# Configurable parameters
###############################################################################
SERVICE_NAME="honeypot"
HONEYPOT_USER="honeypot"
HONEYPOT_GROUP="honeypot"
INSTALL_DIR="/opt/honeypot"
BINARY_NAME="honeypot"              # The name of your compiled binary
LOCAL_BINARY_PATH="./honeypot"      # Where your compiled binary is locally
SYSTEMD_UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
PERMISSIONS="750"                   # Permissions for $INSTALL_DIR

###############################################################################
# 1. Create user and group if they do not exist
###############################################################################
echo ">> Checking if user '$HONEYPOT_USER' exists..."
if id "$HONEYPOT_USER" &>/dev/null; then
  echo "   User '$HONEYPOT_USER' already exists."
else
  echo "   Creating system user '$HONEYPOT_USER'..."
  sudo useradd -r -s /usr/sbin/nologin "$HONEYPOT_USER"
fi

###############################################################################
# 2. Create /opt/honeypot directory if missing
###############################################################################
echo ">> Ensuring $INSTALL_DIR directory exists..."
if [ ! -d "$INSTALL_DIR" ]; then
  echo "   Creating directory $INSTALL_DIR..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo chown "$HONEYPOT_USER":"$HONEYPOT_GROUP" "$INSTALL_DIR"
  sudo chmod "$PERMISSIONS" "$INSTALL_DIR"
else
  echo "   Directory $INSTALL_DIR already exists."
  echo "   Ensuring correct ownership & permissions..."
  sudo chown "$HONEYPOT_USER":"$HONEYPOT_GROUP" "$INSTALL_DIR"
  sudo chmod "$PERMISSIONS" "$INSTALL_DIR"
fi

###############################################################################
# 3. Copy binary to /opt/honeypot if it differs
###############################################################################
echo ">> Checking if $BINARY_NAME needs to be updated..."
LOCAL_CHECKSUM=$(sha256sum "$LOCAL_BINARY_PATH" | awk '{print $1}')
REMOTE_PATH="$INSTALL_DIR/$BINARY_NAME"

if [ -f "$REMOTE_PATH" ]; then
  REMOTE_CHECKSUM=$(sudo sha256sum "$REMOTE_PATH" | awk '{print $1}')
  if [ "$LOCAL_CHECKSUM" = "$REMOTE_CHECKSUM" ]; then
    echo "   Binary already matches the existing one; no copy needed."
  else
    # Verify if the service is already running
    # If it is, we need to stop it first
    if sudo systemctl is-active --quiet "$SERVICE_NAME.service"; then
        echo ">> Stopping $SERVICE_NAME service..."
        sudo systemctl stop "$SERVICE_NAME.service"
    fi

    echo "   Copying updated binary to $REMOTE_PATH..."
    sudo cp "$LOCAL_BINARY_PATH" "$REMOTE_PATH"
    sudo chown "$HONEYPOT_USER":"$HONEYPOT_GROUP" "$REMOTE_PATH"
    sudo chmod +x "$REMOTE_PATH"
  fi
else
  # Verify if the service is already running
  # If it is, we need to stop it first
  if sudo systemctl is-active --quiet "$SERVICE_NAME.service"; then
    echo ">> Stopping $SERVICE_NAME service..."
    sudo systemctl stop "$SERVICE_NAME.service"
  fi

  echo "   No existing binary at $REMOTE_PATH, copying now..."
  sudo cp "$LOCAL_BINARY_PATH" "$REMOTE_PATH"
  sudo chown "$HONEYPOT_USER":"$HONEYPOT_GROUP" "$REMOTE_PATH"
  sudo chmod +x "$REMOTE_PATH"
fi

###############################################################################
# 4. Create or update systemd service file
###############################################################################
echo ">> Installing or updating systemd unit file at $SYSTEMD_UNIT_PATH..."
SERVICE_FILE_CONTENT="[Unit]
Description=Honeypot Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/honeypot
User=${HONEYPOT_USER}
Group=${HONEYPOT_GROUP}
ExecStart=${REMOTE_PATH}
StandardOutput=file:/var/log/honeypot.log
StandardError=file:/var/log/honeypot_err.log
Restart=on-failure

[Install]
WantedBy=multi-user.target
"

# If the file doesn't exist OR the content differs, overwrite it
if [ -f "$SYSTEMD_UNIT_PATH" ]; then
  CURRENT_CONTENT=$(sudo cat "$SYSTEMD_UNIT_PATH")
  if [ "$CURRENT_CONTENT" != "$SERVICE_FILE_CONTENT" ]; then
    echo "   Updating systemd service file because content changed..."
    echo "$SERVICE_FILE_CONTENT" | sudo tee "$SYSTEMD_UNIT_PATH" >/dev/null
  else
    echo "   Systemd unit file already up-to-date."
  fi
else
  echo "   Creating new systemd service file..."
  echo "$SERVICE_FILE_CONTENT" | sudo tee "$SYSTEMD_UNIT_PATH" >/dev/null
fi

###############################################################################
# 5. Reload & restart systemd service
###############################################################################
echo ">> Reloading systemd daemon..."
sudo systemctl daemon-reload

echo ">> Enabling $SERVICE_NAME service to start on boot..."
sudo systemctl enable "$SERVICE_NAME.service"

echo ">> Restarting $SERVICE_NAME service..."
sudo systemctl restart "$SERVICE_NAME.service"

echo ">> Checking $SERVICE_NAME status..."
sudo systemctl status "$SERVICE_NAME.service" --no-pager || true

echo ">> Done! The $SERVICE_NAME service is set up and running."
```

This script installs the honeypot binary, creates a systemd service, and starts the service. It also ensures that the service is stopped before updating the binary or service file. The service logs are written to `/var/log/honeypot.log` and `/var/log/honeypot_err.log`.

The binary is run under the privileges of the `honeypot` user, which is created if it doesn’t exist. The honeypot binary is copied to `/opt/honeypot`, and the systemd service file is created or updated. The service is then reloaded, enabled, and restarted.

A pro-tip I got from Daniel Thompson-Yvetot was to assume the box will be powned and to make it more interesting for the attacker. For example, you change the name of the honeypot sevice to `fastxmrminer.service` and the binary to `fastxmrminer` and the attacker will think they hit the jackpot.

In the current version I kept it simple and straightforward for educational purposes, but you can expand on this idea.

---

# 5. Testing and Monitoring

## 5.1 Live Logs
You can monitor the honeypot logs in real-time using `tail -f`. Here’s how to check the logs:

- SSH into your server.
- Use `tail -f /var/log/honeypot.log` to monitor incoming requests.
- Use `tail -f /var/log/honeypot_err.log` to monitor errors.

I separated the logs to make it easier to distinguish between regular logs and errors. You can customize the log paths and contents to suit your needs.

The `stderr` could benefit from `structured logging` or `tracing`, but for this simple honeypot, we’ll keep it basic.

## 5.2 Simulating an Attack
You can test your honeypot by connecting to it using `telnet` or `nc` from your local machine. Here’s how:

- From your local machine, run `telnet <server_ip> 2222` or `nc <server_ip> 2222` to connect to the honeypot.
- Enter some random text and press Enter.
- Check the logs on the server to see the incoming request.

## 5.3 Gathering Intelligence
Over time, your honeypot will encounter a variety of malicious activities, including port scans, SSH brute-force attempts, and automated exploit scripts. By storing these logs for analysis, you can gain valuable insights into who’s probing your system and what they’re attempting to achieve.

Setting up alerts or notifications can help you identify specific patterns in real-time. Tools like the ELK Stack or Splunk are excellent for log analysis and can be configured to trigger alerts based on defined criteria.

For example, I observed numerous SSH brute-force attempts and port scans targeting my honeypot. It was fascinating to watch the diversity of attacks unfold in real time. One notable instance involved a “Makiko” client—a Rust-based SSH client—attempting to connect, showcasing that Rust is also being utilized for malicious purposes. Shortly after, I detected a Go-based client attempting to connect as well—although, admittedly, Go might not be the ideal language for this kind of job :)

---

# Conclusion
Deploying a custom Rust honeypot on an always-free Oracle Cloud instance gives you hands-on insight into real-world malicious activity. You’ve learned how to code a simple TCP server in Rust, configure Oracle’s networking, manage an OCI's firewall, and centralize logging. With a bit of creativity, you can expand your honeypot to emulate common protocols, capture richer data, or integrate with threat intelligence pipelines. Happy hacking—safely, of course!

---
# GitHub Repository
You can find the code for this project on my GitHub repository [Rust Honeypot](https://github.com/Rust-Trends/honeypot). Feel free to fork, modify, and experiment with it and if you star it - I will be very happy - I may be tempted to write more guides like this one it has been fun to write.

# Author
Bob Peters - [Rust Trends](https://rust-trends.com) - [LinkedIn](https://www.linkedin.com/in/bjhpeters/)

# Further Reading

- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
- [Rust Standard Library](https://doc.rust-lang.org/std/)
- Nice inspiration [Cowrie - Medium to High interaction Honeypot](https://github.com/cowrie/cowrie)*

*Thank you for the tip Dario Lencina Talarico

#!/bin/bash

# Install dependencies
sudo apt update
sudo apt upgrade -y
sudo apt install curl git make jq build-essential gcc unzip wget lz4 pv -y

#Install Go
cd $HOME
VER="1.22.3"
wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz"
rm "go$VER.linux-amd64.tar.gz"
echo "export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin" >> ~/.bash_profile
source ~/.bash_profile
go version

# Install Story-Geth binaries
cd $HOME
wget story-geth https://github.com/piplabs/story-geth/releases/download/v0.9.4/geth-linux-amd64
sudo chmod +x $HOME/story-geth
mv $HOME/story-geth $HOME/go/bin/
mkdir -p "$HOME/.story/story"
mkdir -p "$HOME/.story/geth"

# Install Story
cd $HOME
git clone https://github.com/piplabs/story
cd story
git checkout v0.11.0
go build -o story ./client 
mv $HOME/story/story $HOME/go/bin/

# Initialize Story
story init --network iliad

# Add peers
PEERS=$(curl -sS https://story-testnet-rpc.shachopra.com/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)
echo $PEERS
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.story/story/config/config.toml

# Enable indexer
sed -i -e 's/^indexer = "null"/indexer = "kv"/' $HOME/.story/story/config/config.toml

# Install Cosmovisor
cd $HOME
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.6.0

# Cosmovisor setup
echo "export DAEMON_NAME=story" >> $HOME/.bash_profile
echo "export DAEMON_HOME=/root/.story/story" >> $HOME/.bash_profile
echo "export DAEMON_DATA_BACKUP_DIR=/root/.story/story/data" >> $HOME/.bash_profile
source $HOME/.bash_profile

mkdir -p $HOME/.story/story/cosmovisor/genesis/bin
mkdir -p $HOME/.story/story/cosmovisor/backup
mkdir -p $HOME/.story/story/cosmovisor/upgrades

cp $HOME/go/bin/story $HOME/.story/story/cosmovisor/genesis/bin/

# Create service files

# Geth service file
sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=root
ExecStart=/root/go/bin/story-geth --iliad --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

#Story service file
sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Story Consensus Client
After=network.target

[Service]
User=root
Environment="DAEMON_NAME=story"
Environment="DAEMON_HOME=/root/.story/story"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_DATA_BACKUP_DIR=/root/.story/story/data"
Environment="UNSAFE_SKIP_BACKUP=true"
ExecStart=/root/go/bin/cosmovisor run run
Restart=always
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Download Archival Snapshot
sudo cp $HOME/.story/story/data/priv_validator_state.json $HOME/.story/priv_validator_state.json.backup
sudo rm -rf $HOME/.story/story/data
sudo rm -rf $HOME/.story/geth/iliad/geth/chaindata
mkdir -p $HOME/.story/geth/iliad/geth
wget -O snapshot_story.lz4 https://story-snapshot.shachopra.com:8443/downloads/snapshot_story.lz4
wget -O geth_story.lz4 https://story-snapshot.shachopra.com:8443/downloads/geth_story.lz4
lz4 -c -d snapshot_story.lz4 | pv | sudo tar -xv -C $HOME/.story/story/
lz4 -c -d geth_story.lz4 | pv | sudo tar -xv -C $HOME/.story/geth/iliad/geth/
sudo cp $HOME/.story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json
sudo rm snapshot_story.lz4
sudo rm geth_story.lz4

# Start Story & Story-Geth Node
sudo systemctl daemon-reload && sudo systemctl enable story-geth && sudo systemctl start story-geth
sudo systemctl daemon-reload && sudo systemctl enable story && sudo systemctl start story


echo "Your node is running latest version. Keep track of Story socials for any upgrades & use cosmovisor/upgrades directory for applying automatic upgrades."

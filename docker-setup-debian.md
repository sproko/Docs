# Docker Engine Setup for Debian

## Installation
```bash
# Update package index
sudo apt update

# Install Docker Engine and Docker Compose
sudo apt install docker.io docker-compose-v2

# Start and enable Docker service
sudo systemctl start docker
sudo systemctl enable docker
```

## User Permissions
```bash
# Add your user to docker group (required for non-root access)
sudo usermod -aG docker $USER

# NOTE: You must log out and back in for group membership to take effect
# Or activate immediately in current shell:
newgrp docker
```

## Verify Installation
```bash
# Check Docker service status
sudo systemctl status docker

# Test Docker works
docker ps

# Run hello-world test container
docker run hello-world
```

## Rider Configuration

1. Open Rider
2. **File → Settings → Build, Execution, Deployment → Docker**
3. Click **+** to add a new Docker connection
4. Select **Unix socket**
5. Path: `/var/run/docker.sock`
6. Click **Test Connection** - should show "Connection successful"
7. Click **Apply** and **OK**

## Troubleshooting

### Permission denied on /var/run/docker.sock
- Ensure you added yourself to docker group (see User Permissions above)
- Log out and log back in
- Verify with: `groups` (should see 'docker' in the list)

### KVM/Virtualization errors
- Docker Engine does NOT require KVM or virtualization on Linux
- If you see KVM errors, you likely have Docker Desktop installed (not needed on Linux)
- Remove Docker Desktop and use Docker Engine instead

## Notes

- Docker Engine is native on Linux and does not require virtualization
- Docker Desktop is unnecessary on Linux for most development workflows
- Docker Engine is lighter and faster than Docker Desktop on Linux



1. download `install-tailscale.sh`:
```bash
wget -O install-tailscale.sh https://raw.githubusercontent.com/davidjrb/install-tailscale/main/install-tailscale.sh
```
2. make the script executable:
```bash
chmod +x install-tailscale.sh
```
3. insall nano and create a file called `tskey` containing your tailscale key:
```bash
opkg update && opkg install nano
```
```bash
nano tskey
```
4. run the script:
```bash
./install-tailscale.sh
```

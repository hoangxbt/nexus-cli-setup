# Nexus CLI Auto Setup Script

Script tự động cài đặt và chạy Nexus CLI trên VPS (Ubuntu/Debian).

## Tính năng

-   Cài đặt Nexus CLI tự động
-   **Chạy bằng wallet** - không cần node ID thủ công
-   Tự động tạo node từ wallet
-   Auto-chọn độ khó dựa trên CPU/RAM
-   Chạy background qua pm2 (auto-restart khi reboot)
-   Không cần tương tác (headless mode)

## Cách dùng

```bash
curl -sSf -o setup-nexus.sh https://raw.githubusercontent.com/hoangxbt/nexus-cli-setup/main/setup-nexus.sh
chmod +x setup-nexus.sh
```

### Chạy với wallet (khuyến nghị - không cần node ID)

```bash
./setup-nexus.sh --wallet 0xAbC123...
```

### Chạy với node ID có sẵn

```bash
./setup-nexus.sh --node-id n1abc
```

### Chạy interactive (có menu chọn)

```bash
./setup-nexus.sh
```

## Tùy chọn

| Flag | Mô tả |
|------|-------|
| `--wallet <ADDR>` | Địa chỉ ví, tự động tạo node |
| `--node-id <ID>` | Node ID có sẵn |
| `--difficulty <LEVEL>` | Độ khó: small, medium, large, extra_large, extra_large_2... |
| `--interactive` | Chạy interactive mode |
| `--help` | Xem hướng dẫn |

## Check trạng thái

```bash
pm2 logs nexus-cli   # xem log
pm2 status           # xem trạng thái
pm2 stop nexus-cli   # dừng
```

Xem điểm: https://app.nexus.xyz/compute

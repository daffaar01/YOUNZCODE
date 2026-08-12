# Panduan Add-on YOUNZCODE

Panduan ini menjelaskan cara memasang dan mengelola skill, plugin, MCP server, dan extension VSIX di YOUNZCODE.

## Membuka Add-on Manager

1. Jalankan YOUNZCODE.
2. Klik `ADD-ONS` pada sidebar kiri.
3. Pilih salah satu tindakan:
   - `IMPORT FILE` untuk memasang `SKILL.md`, konfigurasi JSON, atau `.vsix`.
   - `IMPORT FOLDER` untuk memasang folder skill atau plugin.
4. Konfirmasi proses import.
5. Pastikan switch add-on berada dalam kondisi aktif.

Add-on yang diimpor disalin ke:

```text
%LOCALAPPDATA%\YOUNZCODE\addons
```

File atau folder sumber asli tidak dihapus ketika add-on dihapus dari YOUNZCODE.

## Memasang Skill

YOUNZCODE mendukung skill dengan format `SKILL.md` yang kompatibel dengan pola OpenCode dan Claude Code.

### Struktur Folder

```text
code-reviewer/
|-- SKILL.md
`-- references/
    `-- checklist.md
```

### Contoh SKILL.md

```markdown
---
name: Code Reviewer
description: Memeriksa bug, keamanan, regresi, dan kualitas kode.
---

# Code Reviewer

Periksa kode sebelum memberikan kesimpulan.

Prioritaskan:

- Bug dan behavioral regression.
- Masalah keamanan.
- Error handling yang hilang.
- Test yang belum tersedia.
- Perubahan yang terlalu kompleks.

Cantumkan file dan nomor baris pada setiap temuan.
```

### Cara Memasang

1. Buka `ADD-ONS`.
2. Klik `IMPORT FOLDER`.
3. Pilih folder yang berisi `SKILL.md`.
4. Konfirmasi import.
5. Pastikan status skill menunjukkan:

```text
ACTIVE AS AGENT INSTRUCTIONS
```

Anda juga dapat memilih `IMPORT FILE` dan membuka `SKILL.md` secara langsung.

Skill aktif otomatis ditambahkan ke instruksi agent. Skill tidak perlu dipanggil dengan slash command.

## Extension SDK Declarative v1

Plugin YOUNZCODE menggunakan manifest JSON deklaratif. Runtime v1 **tidak** menjalankan JavaScript, executable, entry point, process, akses file, atau akses network dari plugin.

Kontribusi hanya aktif pada workspace tepercaya dan capability harus dideklarasikan secara eksplisit. Capability yang tidak dikenal membuat import ditolak.

### Capability yang tersedia

| Capability | Fungsi | Batas |
|---|---|---|
| `agent.instructions` | Menambahkan instruksi ke agent | 12.000 karakter |
| `commands.declarative` | Menambahkan slash command yang merender prompt agent biasa | 32 command; prompt 4.000 karakter |

### Struktur Folder

```text
security-review/
`-- younzcode-plugin.json
```

### Contoh Manifest v1

```json
{
  "name": "security-review",
  "displayName": "Security Review",
  "version": "1.0.0",
  "apiVersion": "1",
  "description": "Aturan dan command review keamanan.",
  "capabilities": [
    "agent.instructions",
    "commands.declarative"
  ],
  "instructions": "Periksa hardcoded secret, path traversal, command injection, SQL injection, dan SSRF.",
  "contributes": {
    "commands": [
      {
        "name": "secure-review",
        "description": "Review keamanan dengan argumen opsional.",
        "prompt": "Review keamanan untuk: {{args}}"
      }
    ]
  }
}
```

`{{args}}` diganti secara literal dengan teks setelah slash command. Contoh `/secure-review lib/services` menghasilkan prompt agent biasa. Prompt tersebut tetap melewati workspace trust, main-branch warning, context policy, provider policy, dan tool approval YOUNZCODE.

Nama command harus berupa huruf kecil, angka, atau tanda hubung, panjang 2–32 karakter. Command bawaan seperti `/help`, `/review`, `/agents`, dan `/settings` tidak dapat ditimpa. Jika dua plugin aktif mendeklarasikan nama command yang sama, command tersebut tidak dijalankan (fail-closed).

Manifest tanpa capability yang diperlukan, `apiVersion` selain `1`, kontribusi terlalu besar, atau capability seperti `process.execute` akan ditolak. Manifest dibatasi 256 KiB, kedalaman JSON 16, dan 4.096 node; nama maksimal 256 karakter dan deskripsi maksimal 4.000 karakter. Metadata mentah yang tidak digunakan runtime tidak dipersistenkan.

Plugin legacy yang sebelumnya menyimpan `prompt`/`instructions` tanpa capability dimigrasikan ke metadata typed tetapi dinonaktifkan. Pengguna harus mengaktifkannya kembali secara eksplisit sebagai consent terhadap capability `agent.instructions`.

Nama manifest yang dikenali:

```text
younzcode-plugin.json
younzcode.plugin.json
plugin.json
manifest.json
package.json
```

### Cara Memasang

1. Buka `ADD-ONS`.
2. Klik `IMPORT FOLDER`.
3. Pilih folder plugin.
4. Konfirmasi import.
5. Aktifkan switch plugin.
6. Gunakan workspace tepercaya agar kontribusi aktif.

Status plugin tetap menegaskan bahwa code execution dinonaktifkan. Field `entryPoint` atau `main`, bila terdapat pada metadata paket, hanya disimpan sebagai metadata dan tidak pernah dieksekusi.

## Memasang MCP

YOUNZCODE dapat menghubungkan MCP stdio sebagai dynamic tools untuk agent.

MCP hanya dijalankan dalam mode `BUILD`. Seluruh MCP dinonaktifkan dalam `PLAN` mode karena proses eksternal tidak dapat dijamin read-only.

### Contoh Konfigurasi Claude-style

Simpan sebagai `mcp.json`:

```json
{
  "mcpServers": {
    "filesystem-tools": {
      "command": "node",
      "args": [
        "C:\\tools\\filesystem-mcp\\server.js"
      ],
      "env": {
        "MODE": "safe"
      }
    }
  }
}
```

### Contoh Konfigurasi OpenCode-style

```json
{
  "mcp": {
    "local-tools": {
      "type": "local",
      "command": [
        "node",
        "C:\\tools\\local-mcp\\server.js",
        "--safe"
      ]
    }
  }
}
```

### Contoh MCP Python

```json
{
  "mcpServers": {
    "python-tools": {
      "command": "python",
      "args": [
        "-m",
        "my_mcp_server"
      ],
      "env": {
        "PYTHONUNBUFFERED": "1"
      }
    }
  }
}
```

### Nama File yang Dikenali

```text
mcp.json
.mcp.json
mcp-config.json
mcp_config.json
```

### Cara Memasang

1. Pastikan runtime server tersedia, seperti `node`, `python`, atau executable lain.
2. Pastikan command dapat dijalankan dari PowerShell.
3. Buka `ADD-ONS`.
4. Klik `IMPORT FILE`.
5. Pilih konfigurasi JSON MCP.
6. Konfirmasi import.
7. Aktifkan switch MCP.
8. Pilih mode `BUILD` pada composer.
9. Buat `NEW CHAT` jika agent lama sudah dibuat sebelum MCP diaktifkan.

Status MCP stdio:

```text
MCP STDIO TOOLS ACTIVE
```

### Persyaratan Server MCP Stdio

Server harus:

- Menggunakan JSON-RPC MCP melalui stdio.
- Menulis satu pesan JSON per baris ke `stdout`.
- Menulis log biasa ke `stderr`, bukan `stdout`.
- Mendukung `initialize`.
- Mendukung `tools/list`.
- Mendukung `tools/call`.

### MCP HTTP

Konfigurasi HTTP dapat diimpor:

```json
{
  "mcpServers": {
    "remote-docs": {
      "url": "https://mcp.example.com/api",
      "headerReferences": {
        "Authorization": "env:YOUNZCODE_MCP_REMOTE_TOKEN"
      }
    }
  }
}
```

MCP HTTP aktif sebagai dynamic tools pada workspace tepercaya dalam mode `BUILD`. Implementasi mendukung JSON-RPC melalui HTTPS/loopback, respons JSON atau SSE, `Mcp-Session-Id`, discovery `tools/list`, dan `tools/call`.

Batas keamanan transport:

- respons HTTP maksimum 2 MiB sebelum buffering penuh;
- setiap request memiliki absolute deadline 30 detik, termasuk konsumsi body slow-drip;
- discovery maksimum 256 tools;
- output satu tool maksimum 1 MiB berdasarkan ukuran UTF-8;
- input schema maksimum 256 KiB, kedalaman 16, dan 4.096 node;
- event SSE multiline direkonstruksi sesuai framing `data:` dan initialization notification diselesaikan sebelum `tools/list`;
- session kedaluwarsa hanya dipulihkan otomatis untuk operasi idempotent `tools/list`;
- `tools/call` tidak pernah diulang otomatis;
- error HTTP, JSON-RPC, dan log meredaksi header credential serta pola secret umum.

Header credential plaintext—termasuk nama generik seperti `Authorization`, `Cookie`, `X-Api-Key`, `X-Auth-Token`, atau header token/secret sejenis—ditolak saat import, restore metadata lama, dan sebelum request. Gunakan `headerReferences` dengan referensi `env:NAMA_VARIABLE`; nilai hanya dibaca dari process environment saat request dibuat dan tidak disimpan dalam metadata add-on. Jika variable tidak tersedia, koneksi gagal tertutup. OAuth 2.1/PKCE dan secure OS credential store belum tersedia pada versi ini.

## Memasang Extension VSIX

YOUNZCODE dapat mengimpor dan mengelola file `.vsix`.

Format nama file yang disarankan:

```text
publisher.extension-name-1.0.0.vsix
```

### Cara Memasang

1. Buka `ADD-ONS`.
2. Klik `IMPORT FILE`.
3. Pilih file `.vsix`.
4. Konfirmasi import.
5. Extension akan muncul dalam daftar add-on.

Status VSIX:

```text
STORED ONLY - VS CODE API RUNTIME NOT EMBEDDED
```

YOUNZCODE belum menyediakan VS Code Extension Host. Extension yang membutuhkan API berikut tidak dapat dijalankan secara penuh:

```javascript
vscode.commands
vscode.workspace
vscode.window
vscode.languages
```

Gunakan VS Code untuk menjalankan extension VSIX yang membutuhkan runtime API VS Code. Di YOUNZCODE, VSIX saat ini hanya dapat disimpan, diaktifkan atau dinonaktifkan, dan dihapus.

## Mengelola Add-on

Setiap add-on menyediakan:

- Switch aktif: add-on digunakan oleh sesi agent baru.
- Switch nonaktif: add-on tetap terpasang tetapi tidak digunakan.
- Ikon tempat sampah: menghapus salinan add-on dari storage YOUNZCODE.

Setelah mengaktifkan, menonaktifkan, atau menghapus add-on, buat `NEW CHAT` bila sesi yang sedang berjalan belum memuat konfigurasi terbaru.

## Plan Mode dan Add-on

Dalam `PLAN` mode:

- Skill tetap dapat memberikan instruksi analisis.
- Prompt plugin tetap dapat memberikan panduan.
- Tool tulis dinonaktifkan.
- Terminal dinonaktifkan.
- Seluruh MCP eksternal dinonaktifkan.
- Agent hanya dapat membaca, mencari, dan menyusun rencana.

Dalam `BUILD` mode:

- Skill dan prompt plugin aktif.
- MCP stdio aktif jika switch diaktifkan.
- Tool tulis dan terminal mengikuti permission project.

## Troubleshooting MCP

### Command Tidak Ditemukan

Uji command dari PowerShell:

```powershell
node "C:\tools\server.js"
```

atau:

```powershell
python -m my_mcp_server
```

Jika command gagal, tambahkan runtime ke `PATH` atau gunakan path executable absolut pada konfigurasi MCP.

### Tool MCP Tidak Muncul

Periksa bahwa:

- Add-on MCP dalam keadaan aktif.
- Composer menggunakan mode `BUILD`.
- Konfigurasi JSON valid.
- Command dan seluruh argument benar.
- Server mendukung `initialize`, `tools/list`, dan `tools/call`.
- Server tidak menulis log biasa ke `stdout`.
- Sesi chat baru sudah dibuat setelah konfigurasi berubah.

### Path Windows Tidak Valid

Dalam JSON, gunakan backslash ganda:

```json
{
  "command": "C:\\Program Files\\NodeJS\\node.exe"
}
```

Atau gunakan slash:

```json
{
  "command": "C:/Program Files/NodeJS/node.exe"
}
```

## Catatan Keamanan

- Add-on tidak dieksekusi saat proses import.
- Symbolic link dalam folder add-on ditolak.
- Path traversal dan import dari managed add-on directory ditolak.
- Plugin executable dan VSIX tidak dijalankan otomatis.
- MCP stdio berjalan dengan izin pengguna Windows ketika agent menginisialisasinya.
- Aktifkan hanya MCP dari sumber yang dipercaya.
- Jangan menyimpan token atau password dalam manifest yang dibagikan.
- Gunakan `PLAN` mode bila hanya ingin analisis read-only.

# Quick Fix - File Permission Errors

**⏱️ Time Required:** 5-10 minutes

---

## The Problem
Godot can't write to `.godot/imported/` folder.

## The Solution (3 Steps)

### 1️⃣ Fix Permissions

**Windows:**
```
Right-click project folder → Properties → Security → Edit
→ Select your user → Check "Full control" → Apply to all
→ General tab → Uncheck "Read-only" → Apply to all
```

**Linux/Mac:**
```bash
cd /path/to/project
chmod -R u+rwX .
```

---

### 2️⃣ Delete Cache
**Close Godot first!** Then delete the `.godot` folder:

**Windows:** Right-click `.godot` folder → Delete

**Linux/Mac:**
```bash
rm -rf .godot
```

---

### 3️⃣ Reopen & Wait
1. Open Godot
2. Open project
3. **Wait 5-10 minutes** for reimport
4. ✅ Done!

---

## Still Broken?

### Check Disk Space
Need at least 2GB free.

### Check Location
❌ DON'T use:
- `C:\Program Files\`
- OneDrive/Dropbox folders
- Network drives

✅ DO use:
- `C:\Users\YourName\Documents\`
- `D:\Projects\`
- `~/Documents/`

### Antivirus?
Add project folder to antivirus exclusions.

---

## Need More Help?
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for complete instructions.

---

**Last Resort (Windows):**
Run Godot as Administrator (right-click .exe → "Run as administrator")

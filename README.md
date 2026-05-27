# jsonb

A lightweight template compiler that generates JSON from `.jsonb` templates,
using `<#! ... #!>` blocks to embed and escape live bash output.

## Template Format

```json
{
    "bmc": {
        "fw":   "<#! ipmitool bmc info 2>&1 | awk '
            /Firmware Revision/     { fw=$NF }
            /Aux Firmware Rev Info/ { found=1; next }
            found && /0x/           { aux=strtonum($1); found=0 }
            END { printf "%s.%02d", fw, aux }
        ' #!>",
        "ipmi": "<#! ipmitool bmc info 2>&1 | awk '/IPMI Version/ { print $NF }' #!>"
    }
}
```

- `<#! ... #!>` — executes bash, output is JSON-string-escaped inline
- All control flow is plain bash inside the block
- Output is valid JSON — pipe through `jq .` to pretty print

## Build

Dependencies: `meson`, `ninja`, `g++ >= 17`

```bash
meson setup build
cd build
ninja
```

## Install

```bash
sudo ninja install        # installs to /usr/local/bin/jsonb
```

## Usage

```bash
./jsonb template.jsonb            # raw output
./jsonb template.jsonb | jq .     # pretty printed
./jsonb template.jsonb > out.json # save
```

## Project Structure

```
jsonb/
├── src/
│   └── main.cpp
├── meson.build
└── README.md
```


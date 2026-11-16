#!/bin/sh
# Reproduce the tree modifications of umi-mainline's scripts/build.sh (step 1,
# TOUCH=stfts) on a clean linux-6.12.94 git tree, one commit per topic, so the
# result can be exported with git format-patch.
#
#   make-series.sh <umi-mainline checkout> <kernel git tree>
set -eu

WS=$1
TREE=$2
AUTHOR="colorgarden <colorgarden@outlook.com>"
SRCREV=$(git -C "$WS" rev-parse --short HEAD)

commit() {
	git -C "$TREE" add -A
	git -C "$TREE" -c user.name=pmaports -c user.email=pmaports@localhost \
		commit -q --author="$AUTHOR" -m "$1" -m "Imported from github.com/colorgarden/umi-mainline @ $SRCREV for the postmarketOS port. Not upstreamable in this form."
}

# ---- 1. dmaengine: gpi EE offsets -------------------------------------------
python3 -I "$WS/patches/gpi-sm8250-ee-offset.py" "$TREE/drivers/dma/qcom/gpi.c"
commit "dmaengine: qcom: gpi: add sm8250 EE offset variants"

# ---- 2. panel driver ---------------------------------------------------------
cp "$WS/patches/panel-xiaomi-umi.c" "$TREE/drivers/gpu/drm/panel/panel-xiaomi-umi.c"
sed -i 's/\r$//' "$TREE/drivers/gpu/drm/panel/panel-xiaomi-umi.c"
cat >> "$TREE/drivers/gpu/drm/panel/Kconfig" <<'EOF'

config DRM_PANEL_XIAOMI_UMI
	tristate "Xiaomi Mi 10 (umi) AMOLED panel, data-driven from DT"
	depends on OF
	depends on DRM_MIPI_DSI
	depends on BACKLIGHT_CLASS_DEVICE
	select DRM_DISPLAY_DP_HELPER
	select DRM_DISPLAY_HELPER
	help
	  Support for the AMOLED panel used by the Xiaomi Mi 10
	  (SM8250 / "umi"). Panel timing, DSC parameters and the DSI
	  init sequence are all read from the device tree, so a single
	  driver covers every panel variant that device was shipped with
	  (CSOT j2_42_*, Samsung j2_38_*, ...).
EOF
printf 'obj-$(CONFIG_DRM_PANEL_XIAOMI_UMI)\t+= panel-xiaomi-umi.o\n' \
	>> "$TREE/drivers/gpu/drm/panel/Makefile"
commit "drm/panel: add Xiaomi Mi 10 (umi) DSC command-mode AMOLED panel driver"

# ---- 3. ST FTS touchscreen ---------------------------------------------------
ST_DST="$TREE/drivers/input/touchscreen/stfts"
cp -r "$WS/stfts" "$ST_DST"
find "$ST_DST" -type f -exec sed -i 's/\r$//' {} +
printf 'source "drivers/input/touchscreen/stfts/Kconfig"\n' \
	>> "$TREE/drivers/input/touchscreen/Kconfig"
printf 'obj-$(CONFIG_TOUCHSCREEN_ST_FTS)\t+= stfts/\n' \
	>> "$TREE/drivers/input/touchscreen/Makefile"
commit "Input: touchscreen: add vendor-derived ST FTS driver for Xiaomi Mi 10"

# ---- 4. fuel gauge + chargers ------------------------------------------------
PWR="$TREE/drivers/power/supply"
cp "$WS/power/qcom_fg.c" "$WS/power/qcom_pm8150b_charger.c" \
   "$WS/power/bq25970_charger.c" "$WS/power/bq25970_reg.h" "$PWR/"
for f in qcom_fg.c qcom_pm8150b_charger.c bq25970_charger.c bq25970_reg.h; do
	sed -i 's/\r$//' "$PWR/$f"
done
cat >> "$PWR/Kconfig" <<'EOF'

config BATTERY_QCOM_FG
	tristate "Qualcomm PMIC fuel gauge driver"
	depends on IIO
	help
	  Qualcomm PMIC fuel gauge (PM8150B gen3), from the sm8250-mainline
	  bring-up.  Reports capacity/voltage/current of the battery.

config CHARGER_QCOM_SMB5
	tristate "Qualcomm PM8150B PMIC charger driver"
	depends on IIO
	help
	  PM8150B SMB5 charger: VBUS/ICL/FCC control and charger status.

config CHARGER_BQ25970
	tristate "TI BQ25970 battery charger driver"
	depends on I2C
	help
	  TI BQ25970 40W fast charger found in the Mi 10.
EOF
{
	printf 'obj-$(CONFIG_BATTERY_QCOM_FG)\t+= qcom_fg.o\n'
	printf 'obj-$(CONFIG_CHARGER_QCOM_SMB5)\t+= qcom_pm8150b_charger.o\n'
	printf 'obj-$(CONFIG_CHARGER_BQ25970)\t+= bq25970_charger.o\n'
} >> "$PWR/Makefile"
python3 -I "$WS/patches/power-supply-charging-enabled.py" \
	"$TREE/include/linux/power_supply.h" "$PWR/power_supply_sysfs.c"
commit "power: supply: add Qualcomm PM8150B fuel gauge, SMB5 charger and BQ25970"

# ---- 5. device tree ----------------------------------------------------------
DTS="$TREE/arch/arm64/boot/dts/qcom"
for f in sm8250-xiaomi-umi-common.dtsi sm8250-xiaomi-umi.dts umi-dtbo-stubs.dtsi \
	 xiaomi-umi-panels.dtsi sm8250-xiaomi-umi-touch.dtsi xiaomi-umi-battery.dtsi; do
	cp "$WS/dts/$f" "$DTS/$f"
	sed -i 's/\r$//' "$DTS/$f"
done
{
	printf 'dtb-$(CONFIG_ARCH_QCOM)\t+= sm8250-xiaomi-umi.dtb\n'
	printf 'DTC_FLAGS_sm8250-xiaomi-umi\t:= -@\n'
} >> "$DTS/Makefile"
commit "arm64: dts: qcom: add Xiaomi Mi 10 (umi)"

git -C "$TREE" log --oneline | head -6

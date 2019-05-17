SRCS=$(wildcard *.txt)
BINS=$(SRCS:%.txt=bins/%.bin)
HEXS=$(BINS:bins/%.bin=hexes/%.hex)
AS=../statick-tools/target/debug/as
all: $(BINS) $(HEXS)

bins/%.bin: %.txt
	mkdir -p bins
	$(AS) -o $@ $^

hexes/%.hex: bins/%.bin ../scripts/bin2hex.py
	mkdir -p hexes
	../scripts/bin2hex.py $^ > $@

clean:
	rm -rf bins/
	rm -rf hexes/

.PHONY: clean

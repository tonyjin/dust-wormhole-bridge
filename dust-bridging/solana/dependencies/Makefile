.PHONY: all clean

all: wormhole.so mpl_token_metadata.so

clean:
	rm *.so

wormhole.so:
	bash build_wormhole_repo_bpfs.sh
	md5sum -c wormhole_checksum.txt

mpl_token_metadata.so:
	bash build_mpl_token_metadata.sh

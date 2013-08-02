.PHONY: all sass clean

all:
	@ocamlbuild w2wt.otarget
	@cp _build/w2wt.js public

sass:
	@compass compile ./css
	@cp -r ./css/css/ ./public

clean:
	rm -rf _build

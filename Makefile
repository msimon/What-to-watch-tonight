.PHONY: all sass clean

all:
	@ocamlbuild ./web/w2wt.otarget
	@cp ./_build/web/w2wt.js ./web/public

sass:
	@compass compile ./web/css
	@cp -r ./web/css/css/ ./web/public

clean:
	rm -rf ./_build

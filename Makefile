.PHONY: all sass clean

all:
	@ocamlbuild ./api/api.otarget
	@ocamlbuild ./graph/graph.otarget
	@ocamlbuild -I tools/config ./tools/tools.otarget
	@ocamlbuild ./web/w2wt.otarget
	@cp ./_build/web/w2wt.js ./web/public

web:
	@ocamlbuild ./web/w2wt.otarget
	@cp ./_build/web/w2wt.js ./web/public

tools:
	@ocamlbuild ./tools/tools.otarget

sass:
	@compass compile ./web/css
	@cp -r ./web/css/css/ ./web/public

clean:
	rm -rf ./_build

.PHONY: all tools web api graph lib sass clean

TOOLS_BUILD_PATH = ./_build/tools/exec/
TOOLS_PATH = ./tools/

WEB_PUBLIC_PATH = ./web/public

EXEC = $(TOOLS_PATH)moviedb_wrapper.native $(TOOLS_PATH)moviedb_to_w2wt.native $(TOOLS_PATH)learn.native $(TOOLS_PATH)all.native $(WEB_PUBLIC_PATH)/w2wt.js

all: lib tools_in web

web:
	@ocamlbuild ./web/w2wt.otarget
	@cp ./_build/web/w2wt.js $(WEB_PUBLIC_PATH)

tools_in:
	@ocamlbuild -I tools/lib/config ./tools/lib/tools.otarget
	@ocamlbuild -I tools/exec/config -I tools/lib/config ./tools/exec/tools.otarget
	@cp $(TOOLS_BUILD_PATH)moviedb/moviedb_wrapper.native $(TOOLS_PATH)moviedb_wrapper.native
	@cp $(TOOLS_BUILD_PATH)convert/moviedb_to_w2wt.native $(TOOLS_PATH)moviedb_to_w2wt.native
	@cp $(TOOLS_BUILD_PATH)learning/learn.native $(TOOLS_PATH)learn.native
	@cp $(TOOLS_BUILD_PATH)all/all.native $(TOOLS_PATH)all.native

tools: clean-exec tools_in

lib: api graph

api:
	@ocamlbuild ./type/api/api.otarget

graph:
	@ocamlbuild ./type/graph/graph.otarget

sass:
	@compass compile ./web/css
	@cp -r ./web/css/css/ ./web/public

clean:
	@rm -rf ./_build
	@rm -f $(EXEC)
	@echo "Clean: Done!"

clean-exec:
	@rm -rf _build/tools/exec

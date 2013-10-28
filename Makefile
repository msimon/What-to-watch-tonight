.PHONY: all tools web api graph lib sass clean

TOOLS_BUILD_PATH = ./_build/tools/
TOOLS_PATH = ./tools/

WEB_PUBLIC_PATH = ./web/public

EXEC = $(TOOLS_PATH)api_wrapper.native $(TOOLS_PATH)imdb_to_w2wt.native $(TOOLS_PATH)learning.native $(WEB_PUBLIC_PATH)/w2wt.js

all: lib tools web

web:
	@ocamlbuild ./web/w2wt.otarget
	@cp ./_build/web/w2wt.js $(WEB_PUBLIC_PATH)

tools:
	@ocamlbuild -I tools/config ./tools/tools.otarget
	@cp $(TOOLS_BUILD_PATH)api/api_wrapper.native $(TOOLS_PATH)api_wrapper.native
	@cp $(TOOLS_BUILD_PATH)w2wt/imdb_to_w2wt.native $(TOOLS_PATH)imdb_to_w2wt.native
	@cp $(TOOLS_BUILD_PATH)learning_dir/learning.native $(TOOLS_PATH)learning.native

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

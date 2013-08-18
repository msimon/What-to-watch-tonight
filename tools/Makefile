API_NAME := api_wrapper
W2WT_NAME := imdb_to_w2wt
LEARNING_NAME := learning

all:
	@ocamlbuild -I api $(API_NAME).native
	@cp _build/api/$(API_NAME).native $(API_NAME)

	@ocamlbuild -I w2wt $(W2WT_NAME).native
	@cp _build/w2wt/$(W2WT_NAME).native $(W2WT_NAME)

	@ocamlbuild -I learning_dir $(LEARNING_NAME).native
	@cp _build/learning_dir/$(LEARNING_NAME).native $(LEARNING_NAME)

clean:
	@rm -rf _build

NAME := api_wrapper

all:
	@ocamlbuild -I src $(NAME).native
	@cp _build/src/$(NAME).native $(NAME)

clean:
	@rm -rf _build

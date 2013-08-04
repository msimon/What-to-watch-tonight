NAME := api_wrapper

all:
	@ocamlbuild -I api $(NAME).native
	@cp _build/api/$(NAME).native $(NAME)

clean:
	@rm -rf _build

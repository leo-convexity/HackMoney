.EXPORT_ALL_VARIABLES:
NAME = hack-money-client
TAG = latest
PORT = 6000

build:
	@docker build --no-cache --progress=plain . -t $(NAME):$(TAG)

run: build clean
	@docker run -it -p $(PORT):8080 --name $(NAME) -d $(NAME):$(TAG)

clean:
	- @docker rm -f $(NAME)

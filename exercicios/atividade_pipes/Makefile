#Esse makefile só serve para fazer o arquivo a ser enviado pro moodle

.PHONY: submission clean

# Prepara .tar.gz pra submissão no moodle
# Note que antes de preparar o tar.gz, é feito um clean
submission: 
	$(MAKE) -C parallel submission

# Limpa binários
clean:
	$(MAKE) -C parallel      clean
	$(MAKE) -C serial        clean
	$(MAKE) -C exemplo-pipes clean

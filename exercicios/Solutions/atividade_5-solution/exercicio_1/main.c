#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>
#include <semaphore.h>

int produzir(int value);    //< definida em helper.c
void consumir(int produto); //< definida em helper.c
void *ProdutorFunc(void *arg);
void *ConsumidorFunc(void *arg);

int indice_produtor, indice_consumidor, tamanho_buffer;
int* buffer;

// Semáforos usados para controlar o fluxo produtor/consumidor Esses
// semáforos fazem com que o produtor espere por uma posição vaga e
// que o consumidor espera que buffer tenha um produto
sem_t vazio, cheio;

//Você deve fazer as alterações necessárias nesta função e na função
//ConsumidorFunc para que usem semáforos para coordenar a produção
//e consumo de elementos do buffer.
void *ProdutorFunc(void *arg) {
    //arg contem o número de itens a serem produzidos
    int max = *((int*)arg);
    for (int i = 0; i <= max; ++i) {
        int produto;
        if (i == max)
            produto = -1;          //envia produto sinlizando FIM
        else 
            produto = produzir(i); //produz um elemento normal
        sem_wait(&vazio);
        indice_produtor = (indice_produtor + 1) % tamanho_buffer; //calcula o próximo elemento
        buffer[indice_produtor] = produto; //adiciona o elemento produzido à lista
        sem_post(&cheio);
    }
    return NULL;
}

void *ConsumidorFunc(void *arg) {
    while (1) {
        sem_wait(&cheio);
        indice_consumidor = (indice_consumidor + 1) % tamanho_buffer; //Calcula o próximo item a consumir
        int produto = buffer[indice_consumidor]; //obtém o item da lista
        sem_post(&vazio);
        //Podemos receber um produto normal ou um produto especial
        if (produto >= 0)
            consumir(produto); //Consome o item obtido.
        else
            break; //produto < 0 é um sinal de que o consumidor deve parar
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Uso: %s tamanho_buffer itens_produzidos\n", argv[0]);
        return 0;
    }

    tamanho_buffer = atoi(argv[1]);
    int itens = atoi(argv[2]);

    //Iniciando buffer
    indice_produtor = 0;
    indice_consumidor = 0;
    buffer = malloc(sizeof(int) * tamanho_buffer);

    // Inicializa semáforos
    // - vazio começa com tamanho_buffer tokens pois há tamanho_buffer posições vazias em buffer
    // - cheio começa com 0 pois não há nenhum produto no buffer
    //
    //       +-----> sem_t* sendo inicializado
    //       |       +---> 1 se semáforo em memória compartilhada (em SO I)
    //       |       |  +---> tokens no semáforo
    //       v       v  v
    sem_init(&vazio, 0, tamanho_buffer);
    sem_init(&cheio, 0, 0);

    // Cria threads para ProdutorFunc e ConsumidorFunc 
    pthread_t produtor, consumidor;
    pthread_create(&produtor, NULL, ProdutorFunc, &itens);
    pthread_create(&consumidor, NULL, ConsumidorFunc, NULL);

    // Espera threads para ProdutorFunc e ConsumidorFunc 
    pthread_join(produtor, NULL);
    pthread_join(consumidor, NULL);    

    // Destrói semáforos
    sem_destroy(&vazio);
    sem_destroy(&cheio);
    
    //Libera memória do buffer
    free(buffer);

    return 0;
}

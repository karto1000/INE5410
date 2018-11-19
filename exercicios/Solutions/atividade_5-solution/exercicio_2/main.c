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

// Como há multiplos consumidores e múltiplos pordutores, esses
// mutexes são necessários para garantir que apenas um produtor e
// apenas um consumidor mexa na fila de cada vez. Como produtor e
// consumidor alteram variáveis diferentes, cada tipo de thread pode
// ter seu próprio mutex, permitindo que haja um produtor e um
// consumidor ao mesmo tempo operando no buffer.
pthread_mutex_t consumidor_mtx = PTHREAD_MUTEX_INITIALIZER, 
                produtor_mtx = PTHREAD_MUTEX_INITIALIZER;

//Você deve fazer as alterações necessárias nesta função e na função
//ConsumidorFunc para que usem semáforos para coordenar a produção
//e consumo de elementos do buffer.
void *ProdutorFunc(void *arg) {
    //arg contem o número de itens a serem produzidos
    int max = *((int*)arg);
    for (int i = 0; i < /*<=*/ max; ++i) {
        //               ^^^
        int produto; //   |--> trocado por "<" devido ao problema abaixo
        //                v
        // Esse if é problemático se houver mais produtores do que
        // consumidores.  Em especial, se n_cons-n_prods >
        // tamanho_buffer, haverá starvation de
        // (n_cons-n_prods-tamanho_buffer) produtores no término do
        // programa
        //
        //if (i == max)
        //    produto = -1;          //envia produto sinlizando FIM
        //else 
        //    produto = produzir(i); //produz um elemento normal

        produto = produzir(i); //produz um elemento normal

        sem_wait(&vazio);
        pthread_mutex_lock(&produtor_mtx); //seção crítica entre produtores
        indice_produtor = (indice_produtor + 1) % tamanho_buffer; //calcula o próximo elemento
        buffer[indice_produtor] = produto; //adiciona o elemento produzido à lista
        pthread_mutex_unlock(&produtor_mtx);
        sem_post(&cheio);
    }
    return NULL;
}

void *ConsumidorFunc(void *arg) {
    while (1) {
        sem_wait(&cheio);
        pthread_mutex_lock(&consumidor_mtx); // Seção crítica entre consumidores
        indice_consumidor = (indice_consumidor + 1) % tamanho_buffer; //Calcula o próximo item a consumir
        int produto = buffer[indice_consumidor]; //obtém o item da lista
        pthread_mutex_unlock(&consumidor_mtx);
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
    if (argc < 5) {
        printf("Uso: %s tamanho_buffer itens_produzidos n_produtores n_consumidores\n", argv[0]);
        return 0;
    }

    tamanho_buffer = atoi(argv[1]);
    int itens = atoi(argv[2]);
    int n_produtores = atoi(argv[3]);
    int n_consumidores = atoi(argv[4]);

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

    pthread_t produtor[n_produtores], consumidor[n_consumidores];

    // Cria threads para ProdutorFunc e ConsumidorFunc 
    for (int i = 0; i < n_produtores; ++i)
        pthread_create(&produtor[i], NULL, ProdutorFunc, &itens);
    for (int i = 0; i < n_consumidores; ++i)
        pthread_create(&consumidor[i], NULL, ConsumidorFunc, NULL);

    // Espera threads para ProdutorFunc
    for (int i = 0; i < n_produtores; ++i)
        pthread_join(produtor[i], NULL);

    // Importante: Se n_produtores < n_consumidores, serão inseridos
    // n_produtores "-1" na fila, mas n_consumidores-n_produtores 
    // consumidores ficarão esperando por um -1 que nunca chegará. 
    // Precisamos adicionar esses -1 faltantes
    //for (int i = n_produtores; i < n_consumidores; ++i) {
    //    sem_wait(&vazio);
    //    buffer[indice_produtor = (indice_produtor+1) % tamanho_buffer] = -1;
    //    sem_post(&cheio);
    //}

    // Mas note que se n_produtores > n_consumidores, há a
    // possibilidade de um stravation de produtores (veja
    // ProdutorFunc). Para evitar as duas possibilidade de starvation,
    // o main pode assumir a responsabilidade total de produção dos -1
    for (int i = 0; i < n_consumidores; ++i) {
        sem_wait(&vazio);
        buffer[indice_produtor = (indice_produtor+1) % tamanho_buffer] = -1;
        sem_post(&cheio);
    }

    //Agora sim, podemos esperar pelas threads executando ConsumidorFunc
    for (int i = 0; i < n_consumidores; ++i)
        pthread_join(consumidor[i], NULL);
    
    // Destrói semáforos
    sem_destroy(&vazio);
    sem_destroy(&cheio);

    // Destrói mutexes
    pthread_mutex_destroy(&produtor_mtx);
    pthread_mutex_destroy(&consumidor_mtx);

    //Libera memória do buffer
    free(buffer);

    return 0;
}

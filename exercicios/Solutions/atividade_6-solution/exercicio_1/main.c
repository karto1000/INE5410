#include <stdio.h>
#include <semaphore.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>

#define WORKER_LOOPS 20

void *worker1_func(void *arg);
void *worker2_func(void *arg);
extern int operacao_worker1();
extern int operacao_worker2();
extern void imprime_resultado(int total, int* lista, int tam_lista);

int total_computado;
int *lista_de_operacoes;
int proximo_indice;

pthread_mutex_t mutex_total;
pthread_mutex_t mutex_lista;

void *worker1_func(void *arg) {
    for (int i = 0; i < WORKER_LOOPS; ++i) {
        // Uma solução é garantir que os dois mutexes sejam adquiridos
        // na mesma ordem. Antes estava assim:
        //     worker1: mutex_total  --> mutex_lista --> ...
        //     worker2: mutex_lista  --> mutex_total --> ...
        // Agora, ficou assim:
        //     worker1: mutex_lista  --> mutex_total --> ...
        //     worker2: mutex_lista  --> mutex_total --> ...
        
        pthread_mutex_lock(&mutex_lista);
        printf("Worker 1 obteve mutex_lista\n");  
        int operacao = operacao_worker1();
        pthread_mutex_lock(&mutex_total);
        printf("Worker 1 obteve mutex_total\n");

        total_computado += operacao;
        lista_de_operacoes[proximo_indice++] = operacao;

        pthread_mutex_unlock(&mutex_lista);
        printf("Worker 1 liberou mutex_lista\n");
        pthread_mutex_unlock(&mutex_total);
        printf("Worker 1 liberou mutex_total\n");
    }
   
    return NULL;
}

void *worker2_func(void *arg) {
    for (int i = 0; i < WORKER_LOOPS; ++i) {
        pthread_mutex_lock(&mutex_lista);
        printf("Worker 2 obteve mutex_lista\n");
        int operacao = operacao_worker2();
        pthread_mutex_lock(&mutex_total);
        printf("Worker 2 obteve mutex_total\n");

        lista_de_operacoes[proximo_indice] = operacao;
        total_computado += lista_de_operacoes[proximo_indice];
        proximo_indice += 1;

        pthread_mutex_unlock(&mutex_lista);
        printf("Worker 2 liberou mutex_lista\n");
        pthread_mutex_unlock(&mutex_total);
        printf("Worker 2 liberou mutex_total\n");
    }
    return NULL;
}


int main(int argc, char *argv[]) {
    //Inicia as variáveis globais
    proximo_indice = 0;
    lista_de_operacoes = malloc(sizeof(int) * 2*WORKER_LOOPS);
    total_computado = 0;

    //Inicia os mutexes
    pthread_mutex_init(&mutex_lista, NULL);
    pthread_mutex_init(&mutex_total, NULL);

    //Cria as threads do worker1 e worker2.
    pthread_t worker1, worker2;
    pthread_create(&worker1, NULL, worker1_func, NULL);
    pthread_create(&worker2, NULL, worker2_func, NULL);

    //Join nas threads
    pthread_join(worker1, NULL);
    pthread_join(worker2, NULL);

    imprime_resultado(total_computado, lista_de_operacoes, 2*WORKER_LOOPS);

    //Libera mutexes e memória alocada
    pthread_mutex_destroy(&mutex_lista);
    pthread_mutex_destroy(&mutex_total);
    free(lista_de_operacoes);

    return 0;
}

#include <stdio.h>
#include <pthread.h>
#include <semaphore.h>
#include <time.h>
#include <stdlib.h>

// Cada token no semáforo sem_pode_x indica que um "x" pode ser
// impresso sem violar a regra do enunciado. Cada A permite a
// impressão de um B e cada B permite a impressão de um A
sem_t sem_pode_a, sem_pode_b;

FILE* out;

void *thread_a(void *args) {
    for (int i = 0; i < *(int*)args; ++i) {
        sem_wait(&sem_pode_a); // espera pela permissão
        fprintf(out, "A");
        // Importante para que vocês vejam o progresso do programa
        // mesmo que o programa de vocês trave em um sem_wait().
        fflush(stdout);
        sem_post(&sem_pode_b); // permite a impressão de um B
    }
    return NULL;
}

void *thread_b(void *args) {
    for (int i = 0; i < *(int*)args; ++i) {
        sem_wait(&sem_pode_b); //espera pela permissão
        fprintf(out, "B");
        fflush(stdout);
        sem_post(&sem_pode_a); //permite a impressão de um A
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Uso: %s iteracoes\n", argv[0]);
        return 1;
    }
    int iters = atoi(argv[1]);
    srand(time(NULL));
    out = fopen("result.txt", "w");

    pthread_t ta, tb;

    // Inicializa semáforos
    sem_init(&sem_pode_a, 0, 1);
    sem_init(&sem_pode_b, 0, 1);

    // Cria threads
    pthread_create(&ta, NULL, thread_a, &iters);
    pthread_create(&tb, NULL, thread_b, &iters);

    // Espera pelas threads
    pthread_join(ta, NULL);
    pthread_join(tb, NULL);

    //Imprime quebra de linha e fecha arquivo
    fprintf(out, "\n");
    fclose(out);
  
    // Cleanup
    sem_destroy(&sem_pode_a);
    sem_destroy(&sem_pode_b);

    return 0;
}

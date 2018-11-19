#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>
#include <semaphore.h>
#include "bandeja.h"

//Funções definidas em threads.c
void* funcionaria_thread(void*arg);
void* aluno_thread(void* arg);

pthread_t funcionaria;
//sem_t colocar_carne_sem;
//sem_t bandeja_sem;
extern int ru_fechado;

int main(int argc, char **argv) {
    int n_alunos = get_num_alunos(argc, argv);
    printf("Simulando %d alunos...\n", n_alunos); fflush(stdout);
    // Crie uma thread para cada um dos n_alunos alunos
    // Crie uma thread para a funcionária
    // Garanta que o programa só termina quando todos os alunos tiverem
    // terminado de almoçar

    sem_init(&colocar_carne_sem, 0, 1);
    sem_init(&bandeja_sem, 0, 1);

    pthread_t alunos[n_alunos];

    // cria as threads dos alunos
    for(int i = 0; i < n_alunos; i++) {
      pthread_create(&alunos[i], NULL, aluno_thread, NULL);
    }

    // Cria a thread da funcionaria
    pthread_create(&funcionaria, NULL, funcionaria_thread, NULL);


    // espera todos os alunos comerem
    for(int i = 0; i < n_alunos; i++) {
      pthread_join(alunos[i],NULL);
    }

    // diz que o RU vai fechar
    pthread_join(funcionaria, NULL);
    ru_fechado = 1;
    sem_destroy(&bandeja_sem);
    sem_destroy(&colocar_carne_sem);

    return 0;
}

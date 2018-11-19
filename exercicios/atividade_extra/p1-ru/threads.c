#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>
#include <semaphore.h>
#include "bandeja.h"

int ru_fechado;



void* funcionaria_thread(void* arg) {
    while (!ru_fechado) {
      // se não tem bandeja pra colocar espera
      
      colocar_carne();

      //libera o semaforo depois que colocou a carne
    }
    return NULL;
}

void* aluno_thread(void* arg) {
    bandeja_t* minha_bandeja = pegar_bandeja();

    aproximar_bandeja(minha_bandeja);
    // espera que a funcionaria coloque a carne

    if (bandeja_vazia(minha_bandeja))
        fazer_bandejaco();
    else
        comer(minha_bandeja);
    return NULL;
}

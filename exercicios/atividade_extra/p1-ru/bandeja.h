#ifndef BANDEJA_H_
#define BANDEJA_H_
#include <semaphore.h>

typedef struct {
    int carne;
} bandeja_t;

sem_t colocar_carne_sem;
sem_t bandeja_sem;

bandeja_t* pegar_bandeja();
void aproximar_bandeja(bandeja_t* b);
int bandeja_vazia(bandeja_t* b);
void colocar_carne();
void comer(bandeja_t* b);
void fazer_bandejaco();

int get_num_alunos(int argc, char** argv);

#endif /*BANDEJA_H_*/

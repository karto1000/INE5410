#ifndef __COZINHA_H__
#define __COZINHA_H__

#include "pedido.h"
#include <semaphore.h>

sem_t cozinheiros_sem;
sem_t bocas_sem;
sem_t frigideiras_sem;
sem_t garcons_sem;
sem_t balcao_sem;
sem_t pedidos_sem;

extern void cozinha_init(int cozinheiros, int bocas, int frigideiras, int garcons, int tam_balcao);
extern void cozinha_destroy();
extern void processar_pedido(pedido_t p);

#endif /*__COZINHA_H__*/

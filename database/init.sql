CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users(
	id UUID PRIMARY KEY default gen_random_uuid() ,
	name varchar(255) not null,
	email varchar(255) not null unique,
	password varchar(255) not null,
  avatar varchar(255)
); 

CREATE TABLE exercises (
  id UUID PRIMARY KEY default gen_random_uuid(),
  name VARCHAR(255) not null,
  series int not null,
  repetitions int,
  group_name VARCHAR(255)not null,
  demo VARCHAR(255),
  thumb VARCHAR(255),
  created_at TIMESTAMP  DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);


CREATE TABLE exercises_histories (
  id SERIAL PRIMARY KEY,
	user_id UUID,
	exercise_id UUID,
	created_at TIMESTAMP  DEFAULT CURRENT_TIMESTAMP,
	CONSTRAINT exercises_histories_user_table_fk FOREIGN KEY(user_id) REFERENCES users(id),
	CONSTRAINT exercises_histories_exercises_table_fk FOREIGN KEY(exercise_id) REFERENCES exercises(id)
);

CREATE TABLE refresh_tokens (
  refresh_token VARCHAR(255) NOT NULL UNIQUE,
  user_id UUID NOT NULL,
  expires_in TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	CONSTRAINT refresh_tokens_user_table_fk FOREIGN KEY(user_id) REFERENCES users(id)
);


INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Supino inclinado com barra',4,12,'peito','supino_inclinado_com_barra.gif','supino_inclinado_com_barra.png');

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Crucifixo reto',3,12,'peito','crucifixo_reto.gif','crucifixo_reto.png');

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Supino reto com barra',3,12,'peito','supino_reto_com_barra.gif','supino_reto_com_barra.png');
  
INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Francês deitado com halteres',3,12,'tríceps','frances_deitado_com_halteres.gif','frances_deitado_com_halteres.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Corda Cross',4,12,'tríceps','corda_cross.gif','corda_cross.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Barra Cross',3,12,'tríceps','barra_cross.gif','barra_cross.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Tríceps testa',4,12,'tríceps','triceps_testa.gif','triceps_testa.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Levantamento terra',3,12,'costas','levantamento_terra.gif','levantamento_terra.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Pulley frontal',3,12,'costas','pulley_frontal.gif','pulley_frontal.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Pulley atrás',4,12,'costas','pulley_atras.gif','pulley_atras.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Remada baixa',4,12,'costas','remada_baixa.gif','remada_baixa.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Serrote',4,12,'costas','serrote.gif','serrote.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Rosca alternada com banco inclinado',4,12,'bíceps','rosca_alternada_com_banco_inclinado.gif','rosca_alternada_com_banco_inclinado.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Rosca Scott barra w',4,12,'bíceps','rosca_scott_barra_w.gif','rosca_scott_barra_w.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Rosca direta barra reta',3,12,'bíceps','rosca_direta_barra_reta.gif','rosca_direta_barra_reta.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Martelo em pé', 3, 12, 'bíceps', 'martelo_em_pe.gif', 'martelo_em_pe.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Rosca punho', 4, 12, 'antebraço', 'rosca_punho.gif', 'rosca_punho.png'  );  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Leg press 45 graus', 4, 12, 'pernas', 'leg_press_45_graus.gif', 'leg_press_45_graus.png'   );  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Extensor de pernas', 4, 12, 'pernas', 'extensor_de_pernas.gif', 'extensor_de_pernas.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Abdutora', 4, 12, 'pernas', 'abdutora.gif', 'abdutora.png' );  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Stiff', 4, 12, 'pernas', 'stiff.gif', 'stiff.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Neck Press', 4, 10, 'ombro', 'neck-press.gif', 'neck-press.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Desenvolvimento maquina', 3, 10, 'ombro', 'desenvolvimento_maquina.gif', 'desenvolvimento_maquina.png');  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Elevação lateral com halteres sentado', 4, 10, 'ombro', 'elevacao_lateral_com_halteres_sentado.gif', 'elevacao_lateral_com_halteres_sentado.png' );  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Encolhimento com halteres', 4, 10, 'trapézio', 'encolhimento_com_halteres.gif', 'encolhimento_com_halteres.png' );  

INSERT INTO exercises(name, series, repetitions, group_name, demo, thumb) 
  VALUES('Encolhimento com barra', 4, 10, 'trapézio', 'encolhimento_com_barra.gif', 'encolhimento_com_barra.png' );
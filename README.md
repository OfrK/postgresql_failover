# postgresql failover with docker
**легенда** 
- 192.168.48.20 - virtual ip
- 192.168.48.21 - container pgpool node 1
- 192.168.48.22 - container pgpool node 2
- 192.168.48.23 - container postgres repmgr node 1
- 192.168.48.24 - container postgres repmgr node 2

##Требования:

1) 2 виртуальные машины с linux kernel version > 4.0
2) доступ в интернет на виртуальных машинах


##Postgresql Repmgr and Pgpool-II in docker container
Postgresql + repmgr + pgpool II с автоматическим восстановлением упавшей ноды Запускаются внутри докера на linux, используется macvlan или ipvlan для поднятия интерфейса pgpool II
https://www.postgresql.org/docs/11/index.html
https://repmgr.org/docs/current/index.html
https://www.pgpool.net/docs/latest/en/html/
https://docs.docker.com/engine/
 
###Состав

Ниже представлен список файлов, в нем присутствует конфигурация контейнера, а так же сервисов.
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/1.png)
1) node_1 - совокупность контейнеров для ноды
2) configuration - файлы конфигурации для сервисов
3) scripts - содержит скрипты для сервисов  с их надстройками
4) pgpool - контейнер сервиса pgpool-II
5) postgresql_repmgr - контейнер сервисов postgresql и repmgr


 
###Установка Docker на linux
1) Docker engine https://docs.docker.com/engine/install/
2) Docker-compose https://docs.docker.com/compose/install/
3) Docker network https://docs.docker.com/network/network-tutorial-macvlan/ (kernel linux)
 
##Разворачивание контейнеров
###Подготовка docker-compose
Первое что нужно подготовить - docker-compose, зеленым цветом подсвечено что необходимо менять.\
Настроить сеть докера, в данной сборке можно использовать macvlan и ipvlan сеть, задается в "driver: " \
https://docs.docker.com/network/ все по сети \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/2.png) 

###Настройка Postgresql and repmgr
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/3.png)

###Настройка pgpool-II
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/4.png) 

При желании можно указать свои пути для хранения изменяемых данных 
ссылка на документацию https://docs.docker.com/storage/volumes/ \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/5.png) 
 
###Подготовка конфигураций для сервисов
После редактирования docker-compose можно приступать к настройки конфигураций, данная инструкция повторяется для каждой ноды в кластере один раз и после разворачивается сколько угодно, если не меняются ip адреса
Список конфигураций для postgresql и repmgr \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/6.png) 

Данные файлы необходимо настроить администратору БД, за исключением repmgr.conf совместно с системным администратором 
Далее необходимо настроить скрипты для отказоустойчивости \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/7.png) 
 
Открываем failover.conf, в нем нужно отредактировать строки: 15, 22-23 \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/8.png) 
 
Последнее что нужно редактировать это pgpool-II, pool_hba должен быть как pg_hba \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/9.png) 
 
pcppass добавить строки ip:9898:repmgr user:repmgr password всех машин которые будут нодами в данном кластере \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/10.png) 
 
pcp хранит записи пользователь и хэш пароля, генерируется при сборке, можно добавить свои записи \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/11.png) 
 
pool_passwd содержит записи для доступа пользователей через virtual ip ( delegate ip) pgpool-II , user and md5(pg_shadow postgresql)

##Сборка
Чтобы собрать образ, необходимо перейти в директорию где находится docker-compose(file) и выполнить команду docker-compose up --build
После успешного выполнения можно работать с контейнерами
###Настройка ssh в контейнерах
Для работы скриптов по отказоустойчивости нужен ssh для пользователя postgres , при сборке ключи были созданы, их необходимо перенести по следующей схеме \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/12.png) 
 
"container postgres repmgr" должен ходить на "container pgpool" delegate_ip (pgpool.conf) и на другие "container postgres repmgr"

###Настройка master slave в контейнере
После успешной сборки осталось только зарегистрировать мастера и подключить к нему слейвы
1.	Чтобы посмотреть имена контейнеров, выполните "docker ps"
2.	Заходим в контейнер с postgres где будет будущий мастер "docker exec -it -u postgres(or root) 'имя контейнера' bash"
3.	 запускаем скрипт "initialize_node.sh primary". После чего нода станет мастером.
4.	Проверим состояние кластера "/usr/pgsql-11/bin/repmgr cluster show" и выпишем строку Connection string , пример (host=192.168.48.23 port=5432 dbname=repmgr user=repmgr)
5.	Далее выполняем пункты 1-4 на слевах, за исключением пункта 3, в нем мы пишем initialize_node.sh "Connection string", пример initialize_node.sh "host=192.168.48.23 port=5432 dbname=repmgr user=repmgr", после чего появится слейв

###Проверка работоспособности
Зайти в контейнер под пользователем postgres \
docker exec -it -u postgres 'имя контейнера' bash \
Проверим состояние кластера в repmgr"/usr/pgsql-11/bin/repmgr cluster show" \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/13.png) 

Проверим состояние кластера в pgpool “psql --port=5434  --host=192.168.48.20 --username=repmgr --dbname repmgr  -c "show pool_nodes" –w” \
![](https://github.com/g-tamanov/postgresql_failover/raw/master/images_readme/14.png) 




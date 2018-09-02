# Как запустить Glue?

1. Установите [Tarantool](https://www.tarantool.io/en/download/)
1. Клонируйте репозиторий: ```git clone https://github.com/vvzvlad/glue.git && cd glue```
1. Установите http: ```sudo tarantoolctl rocks install http```
1. Установите mqtt: ```sudo tarantoolctl rocks install mqtt```
1. Установите dump: ```sudo tarantoolctl rocks install dump```
1. Установите cron-parser: ```sudo tarantoolctl rocks install cron-parser```
1. Запустите серверную часть: ```./glue.lua``` (запустится HTTP сервер на порту 8080)
1. Установите и запустите панель управления [Glue Webapp](https://github.com/vvzvlad/glue_web_app)
1. При необходимости, укажите адрес HTTP сервера Tarantool на странице настроек в панели управления, если он отличается от localhost:8080

# Что это?
- Glue — это система управления IoT-устройствами, предоставляющая:
- интерфейс для разработки драйверов, которые получают и конвертируют данные с устройств
- интерфейс для разработки скриптов, которые обеспечивают взаимодействие устройств между собой
- центральную шину данных для хранения текущих данных подключенных устройств
- панель управления для визуализации данных, просмотра логов и настройки системы

# Документация

[DOCUMENTATION.md](DOCUMENTATION.md)

# Зачем?
Устройства интернета вещей — весьма различны в своих возможностях и характеристиках. Из-за физических ограничений они оперируют множеством протоколов и стандартов: modbus, ethernet, knx, 6lowpan, zigbee, LoRa, и многими другими.

Принять какой-либо стандарт в качестве единого невозможно, так как на данном этапе развития технологий невозможно обеспечить избыточность в стандарте, достаточную для удовлетворения всех задач одновременно: кому-то необходима высокая скорость связи и mesh-сеть, кому-то большая дальность, в каких-то условиях вообще невозможно использовать радио-протоколы.

Таким образом, текущая ситуация в современном интернете вещей заключается в том, что у нас есть множество стандартов передачи данных, и решения этой проблемы в ближайшие годы не предвидится.

## Чем Glue не является?
- Генератором красивых веб-панелей управления
- Графическим конфигуратором
- Панелью управления умным домом
- Средством настройки для устройств, которые производим мы
- Генератором прошивок для Arduino
- Монструозной системой, на обучение которой надо потратить месяц
- Закрытой вендорским продуктом с принципом "что дали тем и пользуйтесь"
- Системой с готовым набором драйверов и скриптов на все случаи жизни

## Тогда что такое Glue?
- Система, ориентированная на разработчиков: предполагается, что писать код вам привычнее, чем расставлять курсором элементы
- Система, ориентированная на простоту разработки: по нашему мнению, разработчик логики не должен вникать в работу системы на низком уровне.
- Системой с открытом кодом: Glue(а так же Tarantool и Lua, которые лежат в его основе) имеют открытый код, что позволяет легко предлагать и дописывать новый функционал.

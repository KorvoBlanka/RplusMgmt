package RplusMgmt::L10N::ru;

use Rplus::Modern;

use base qw(RplusMgmt::L10N);

our %Lexicon = (
    # A
    q{analytics} => 'аналитика',
    q{add} => 'добавить',
    q{agent} => 'агент',
    q{additional} => 'дополнительно',
    q{added} => 'добавлено',
    q{add date} => 'дата добавления',
    q{apply} => 'применить',
    q{active} => sub {
        my $lf = shift;
        my @x = qw/активно активные/;
        return $x[($_[0] || 1) - 1];
    },
    q{any} => 'любой',
    q{all agents} => 'все агенты',
    q{addr} => 'адрес',
    q{address} => 'адрес',
    q{ap} => 'кв',
    q{ar} => 'сот',
    q{agency} => 'агентство',
    q{advanced options} => 'дополнительные параметры',
    q{additional description} => 'дополнительное описание',
    q{additional information} => 'дополнительная информация',
    q{add files...} => 'добавить файлы...',

    q{action completed successfully} => 'действие успешно завершено',
    q{an error occurred while subscribing client} => 'ошибка при оформлении подписки для клиента',

    # B
    q{balcony} => 'балкон',
    q{bathroom} => 'санузел',

    # C
    q{configuration} => 'конфигурация',
    q{company} => 'компания',
    q{companies} => 'компании',
    q{company name} => 'название компании',
    q{close} => 'закрыть',
    q{cancel} => 'отмена',
    q{change photo} => 'изменить фото',
    q{changed} => 'изменено',
    q{client} => 'клиент',
    q{city} => 'город',
    q{condition} => 'состояние',

    q{cannot save subscription without queries} => 'не могу сохранить подписку без запросов',

    # D
    q{dispatcher} => 'диспетчер',
    q{description} => 'описание',
    q{date range} => 'диапазон дат',
    q{date} => 'дата',

    # E
    q{export media} => 'выгрузка прессы',
    q{empty} => 'пусто',
    q{end date} => 'дата окончания',
    q{export} => 'экспорт',

    # F
    q{found} => 'найдено',
    q{from} => 'от',
    q{floor} => 'этаж',
    q{floors} => 'этажи',

    # G
    q{group name} => 'название группы',
    q{geo} => 'карта',

    # H
    q{house} => 'дом',
    q{hectare} => 'га',

    # I
    q{inactive} => 'неактивно',

    q{invalid login or password} => 'неверный логин или пароль',

    # K
    q{keywords} => 'ключевые слова',
    q{kitchen} => 'кухня',

    # L
    q{landmark} => 'ориентир',
    q{landmarks} => 'ориентиры',
    q{login} => 'логин',
    q{loading...} => 'загрузка...',
    q{limit} => 'лимит',
    q{levels} => 'уровней',
    q{land} => 'земля',
    q{living} => 'жилая',

    # M
    q{mediator} => 'посредник',
    q{mediators} => 'посредники',
    q{mediator name} => 'имя посредника',
    q{main} => 'главная',
    q{manager} => 'менеджер',

    # N
    q{name} => sub {
        my $lh = shift;
        my @x = qw/имя название/;
        return $x[($_[0] || 1) - 1];
    },
    q{new} => 'новый',
    q{new user} => 'новый пользователь',
    q{new password} => 'новый пароль',
    q{no photo} => 'нет фото',
    q{nobody} => 'не задано',
    q{num} => 'номер',

    # O
    q{open} => 'открыть',
    q{offer} => sub {
        my $lf = shift;
        my @x = qw/предложение предл./;
        return $x[($_[0] || 1) - 1];
    },
    q{owner} => 'собственник',
    q{owner phone} => 'телефон собственника',

    # P
    q{phone} => 'телефон',
    q{phones} => 'телефоны',
    q{phone num} => 'телефон',
    q{password} => 'пароль',
    q{profile} => 'профиль',
    q{Public / Name} => 'Видимое клиентам / Имя',
    q{Public / Phone num} => 'Видимое клиентам / Телефон',
    q{public visible name} => 'имя агента (для клиентов)',
    q{public visible phone num} => 'телефон агента (для клиентов)',
    q{Please Sign In} => 'Вход в систему',
    q{photo} => 'фото',
    q{photos} => 'фотографии',
    q{price} => 'цена',

    q{phone num cannot be empty} => 'номер телефона не указан',

    # Q
    q{query} => 'запрос',
    q{queries} => 'запросы',
    q{query cannot be empty} => 'запрос не может быть пустым',

    # R
    q{realty} => 'недвижимость',
    q{role} => 'роль',
    q{rent} => 'аренда',
    q{remember me} => 'запомнить',
    q{rooms} => 'комнаты',
    q{SMS} => 'СМС',

    # S
    q{search} => 'поиск',
    q{services} => 'сервисы',
    q{subscription} => 'подписка',
    q{subscriptions} => 'подписки',
    q{sublandmarks} => 'подориентиры',
    q{signed in as} => 'вы вошли как',
    q{save} => 'сохранить',
    q{saving...} => 'сохранение...',
    q{sale} => 'продажа',
    q{sign in} => 'вход',
    q{save subscription} => 'сохранить подписку',
    q{set} => 'установить',
    q{state} => 'статус',
    q{street} => 'улица',
    q{scheme} => sub {
        my $lf = shift;
        my @x = qw/планировка план./;
        return $x[($_[0] || 1) - 1];
    },
    q{square} => 'площадь',
    q{source} => 'источник',
    q{start upload} => 'начать загрузку',

    # T
    q{type} => 'тип',
    q{to} => 'до',
    q{total} => 'всего',

    # U
    q{user} => 'пользователь',
    q{users} => 'пользователи',

    # W
    q{weight (in group)} => 'вес',
    q{work info} => 'рабочая инф.',

    _AUTO => 1
);

1;

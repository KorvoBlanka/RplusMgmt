package Rplus::Export::Present;

use Rplus::Modern;

use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Rplus::Implementation::RealtyParamName qw(get_realty_param_names);
use Rplus::Implementation::Phone qw(get_human_phone_num);

use Rplus::DB;

use RTF::Writer;
use Text::Trim;
use List::MoreUtils qw(all none any);

# 1 => Презент
my $MM_ID = 1;

sub __get_human_sum {
    my $sum = shift;

    return $sum unless $sum > 0;

    my ($m, $ths) = (($sum - $sum%1000)/1000, $sum%1000);
    my $human_sum;
    $human_sum = "$m млн." if $m;
    $human_sum .= ($m ? ' ' : '')."$ths тыс." if $ths;

    return $human_sum;
}

# Дайджест недвижимости для презента
sub __serialize_4ad {
    my ($realty, $param_names) = @_;

    return {} unless defined $realty;

    my $realty_map = {};

    $realty_map->{'street'} =
        $realty->street->name.
        ((none { $realty->street->type->short_name eq $_ } ('ул.', 'кв-л.')) ? " ".$realty->street->type->short_name : '');
    $realty_map->{'sublandmark'} = $realty->sublandmark->name if $realty->sublandmark_id;

    my $ap_scheme = $param_names->{'ap_scheme'};
    my $house_type = $param_names->{'house_type'};
    my $room_scheme = $param_names->{'room_scheme'};
    my $ap_condition = $param_names->{'ap_condition'};
    my $balcony = $param_names->{'balcony'};
    my $bathroom = $param_names->{'bathroom'};
    my $tag = $param_names->{'tag'};

    my @realty_digest;
    # Кол-во комнат (для частных домов и коттеджей)
    if (any {$realty->realty_type eq $_} ('c', 'h')) {
        push @realty_digest, $realty->rooms_count."-комн." if $realty->rooms_count;
    }
    # Планировка недвижимости (кроме малосемеек, для них указывается ниже)
    if ((($realty->ap_scheme_id)//0) != 7) {
        push @realty_digest, $ap_scheme->{$realty->ap_scheme_id} if $realty->ap_scheme_id && $ap_scheme->{$realty->ap_scheme_id};
    }
    # Тип дома
    push @realty_digest, $house_type->{$realty->house_type_id} if $realty->house_type_id && $house_type->{$realty->house_type_id};
    # Этаж/Этажность (отдельно для частых домов и коттеджей)
    if (any {$realty->realty_type eq $_} ('c', 'h')) {
        push @realty_digest, $realty->floors_count." эт." if $realty->floors_count;
    } else {
        push @realty_digest, (
            (all { defined $_ } ($realty->floor, $realty->floors_count)) ? # Заданы этаж/этажность
            $realty->floor."/".$realty->floors_count : $realty->floor." эт."
        ) if defined $realty->floor;
    }
    # Планировка комнат
    push @realty_digest, $room_scheme->{$realty->room_scheme_id} if $realty->room_scheme_id && $room_scheme->{$realty->room_scheme_id};
    # Состояние
    push @realty_digest, $ap_condition->{$realty->ap_condition_id} if $realty->ap_condition_id && $ap_condition->{$realty->ap_condition_id};
    # Площадь
    push @realty_digest, (
        (all { defined $_ } ($realty->square_total, $realty->square_living, $realty->square_kitchen)) ? # Заданы 3 площади
        join('/', grep { s/\./,/ || 1 } ($realty->square_total, $realty->square_living, $realty->square_kitchen)) : ($realty->square_total =~ s/\./,/r)." кв.м."
    ) if defined $realty->square_total;
    # Балкон
    push @realty_digest, $balcony->{$realty->balcony_id} if $realty->balcony_id && $balcony->{$realty->balcony_id};
    # Санузел
    push @realty_digest, $bathroom->{$realty->bathroom_id} if $realty->bathroom_id && $bathroom->{$realty->bathroom_id};
    # Теги
    # Отключены 27.08.2012
    #push @realty_digest, map { $param_names->{'tag'}->{$_->id} } grep { $param_names->{'tag'}->{$_->id} } @{$realty->tags};

    # 5 фраз с описания
    if ($realty->description) {
        my @desc = grep { $_ } trim(split(/,/, $realty->description));
        push @realty_digest, join(', ', splice(@desc, 0, 5)) if $#desc > -1;
    }

    $realty_map->{'digest'} = join ', ', @realty_digest;
    $realty_map->{'agency_price'} = __get_human_sum($realty->agency_price)." руб." if $realty->agency_price;
    $realty_map->{'agency_phones'} = (
        Rplus::Settings->get('present_add_agent_phone') ?
        ($realty->agent->public_phone_num//get_human_phone_num($realty->agent->phone_num)).", " : ''
    ).Rplus::Settings->get('present_agency_phones');

    # Заголовок
    if ($realty->realty_type eq 'r' || (($realty->ap_scheme_id)//0) == 6) {
        $realty_map->{'title'} = "Комн.";
    } elsif ((($realty->ap_scheme_id)//0) == 7) {
        $realty_map->{'title'} = "Малосем.";
    } elsif ($realty->realty_type eq 'c') {
        $realty_map->{'title'} = "Коттедж";
    } elsif ($realty->realty_type eq 'h') {
        $realty_map->{'title'} = "Дом";
    } else {
        $realty_map->{'title'} = $realty->rooms_count."-комн.";
    }

    return $realty_map;
}

sub export2 {
    my $buf;
    my $rtf = RTF::Writer->new_to_string(\$buf);
    $rtf->prolog('charset' => 'ansicpg1251', colors => [undef, [255,0,0], [0,0,255], [255,255,0]]);

    # Сокращения
    my $param_names = get_realty_param_names($MM_ID, 'export');
    # Ориентиры
    my @landmarks;
    my $landmark_iter = Rplus::Model::Landmark::Manager->get_objects_iterator(query => [ type => 'p' ], sort_by => 'name');
    while (my $landmark = $landmark_iter->next) {
        push @landmarks, { id => $landmark->id, name => $landmark->name };
    }
    # Отсортируем, исходя из индекса в названии
    @landmarks = sort { ($a->{'name'} =~ /^\[(\d+)\]/)[0] <=> ($b->{'name'} =~ /^\[(\d+)\]/)[0] || fc($a->{'name'}) cmp fc($b->{'name'}) } @landmarks;

    local *__write  = sub {
        my ($query_base, $par_title) = @_;

        # Группируем по ориентирам
        for my $l (@landmarks) {
            my $q = "t1.landmarks && '{".$l->{'id'}."}'";
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [ @$query_base, \$q ],
                sort_by => 'street.name',
                with_objects => ['street']
            );
            my @r;
            while (my $realty = $realty_iter->next) {
                my $realty_map = __serialize_4ad($realty, $param_names);
                push @r, [\'\fi400\b', $realty_map->{'street'}];
                push @r, " (".$realty_map->{'sublandmark'}.")" if $realty_map->{'sublandmark'};
                push @r, ".";
                push @r, sprintf(" %s (%s) %s %s\n", $realty_map->{'title'}, $realty_map->{'digest'}, $realty_map->{'agency_price'}, $realty_map->{'agency_phones'});
            }
            if ($#r > -1) {
                $rtf->paragraph(\'\sa400\qc\b', ($par_title =~ s/^(.+?)\.?$/$1/r).". ".($l->{'name'} =~ s/^(\[\d+\] ?)?(.+)$/$2/r));
                $rtf->paragraph(\'\sa400', @r);
            }
        }

        # Что не попало в ориентиры
        my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
            query => [
                @$query_base,
                \"NOT t1.landmarks && ARRAY(SELECT id FROM landmarks WHERE type = 'p')"
            ],
            sort_by => 'street.name',
            with_objects => ['street']
        );
        my @r;
        while (my $realty = $realty_iter->next) {
            my $realty_map = __serialize_4ad($realty, $param_names);
                my @x;
                push @x, [\'\fi400\b', $realty_map->{'street'}];
                push @x, " (".$realty_map->{'sublandmark'}.")" if $realty_map->{'sublandmark'};
                push @x, ".";
                push @x, sprintf(" %s (%s) %s %s\n", $realty_map->{'title'}, $realty_map->{'digest'}, $realty_map->{'agency_price'}, $realty_map->{'agency_phones'});
                if ($realty->latitude && $realty->longitude) {
                    push @r, @x;
                } else {
                    # Выделение желтым цветом
                    push @r, [\'\highlight3', @x];
                }
        }
        if ($#r > -1) {
            $rtf->paragraph(\'\sa400\qc\b', ($par_title =~ s/^(.+?)\.?$/$1/r).". ОСТАЛЬНОЕ");
            $rtf->paragraph(\'\sa400', @r);
        }
    };

    # Комнаты, малосемейки
    my $q = "t1.export_mass_media && '{".$MM_ID."}'";
    my @query_base = (
        state => 'work',
        '!agent_id' => undef,
        '!street_id' => undef,
        or => [
            and => [ realty_type => ['a'], ap_scheme_id => [6, 7] ], # Общежития, малосемейки
            realty_type => 'r'
        ],
        agency_price => { gt => 0 },
        offer_type => ['sale', 'exchange'], # Продажа, обмен
        \$q
    );
    __write(\@query_base, "КОМНАТЫ");

    # 1-4 комнатные квартиры
    for my $r (1..4) {
        my $q = "t1.export_mass_media && '{".$MM_ID."}'";
        my @query_base = (
            state => 'work',
            '!agent_id' => undef,
            '!street_id' => undef,
            realty_type => 'a',
            '!ap_scheme_id' => [6, 7], # Не Общежития, не малосемейки
            rooms_count => $r,
            agency_price => { gt => 0 },
            offer_type => ['sale', 'exchange'], # Продажа, обмен
            \$q
        );
        __write(\@query_base, "$r КОМН.");
    }

    # Многокомнатные (> 4 комнат)
    {
        my $q = "t1.export_mass_media && '{".$MM_ID."}'";
        my @query_base = (
            state => 'work',
            '!agent_id' => undef,
            '!street_id' => undef,
            realty_type => 'a',
            rooms_count => { gt => 4 },
            agency_price => { gt => 0 },
            offer_type => ['sale', 'exchange'], # Продажа, обмен
            \$q
        );
        __write(\@query_base, "МНОГОКОМН.");
    }

    # Частные дома и коттеджи
    {
        my $q = "t1.export_mass_media && '{".$MM_ID."}'";
        my @query_base = (
            state => 'work',
            '!agent_id' => undef,
            '!street_id' => undef,
            realty_type => ['h', 'c'],
            agency_price => { gt => 0 },
            offer_type => ['sale', 'exchange'], # Продажа, обмен
            \$q
        );
        __write(\@query_base, "ЧАСТНЫЕ ДОМА И КОТТЕДЖИ");
    }

    $rtf->close;
    return $buf;
}

1;

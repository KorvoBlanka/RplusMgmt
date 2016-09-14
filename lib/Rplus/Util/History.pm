package Rplus::Util::History;

use Rplus::Modern;
use Rplus::Model::HistoryRecord::Manager;

use Rplus::Model::DictApScheme::Manager;
use Rplus::Model::DictBalcony::Manager;
use Rplus::Model::DictBathroom::Manager;
use Rplus::Model::DictCondition::Manager;
use Rplus::Model::DictHouseType::Manager;
use Rplus::Model::DictRoomScheme::Manager;

use Rplus::Model::Media::Manager;

use Rplus::Model::RealtyCategory::Manager;
use Rplus::Model::RealtyType::Manager;
use Rplus::Model::RealtyOfferType::Manager;
use Rplus::Model::RealtyState::Manager;

use JSON;

use Exporter qw(import);
our @EXPORT_OK = qw(realty_record client_record subscription_record task_record mediator_record notification_record get_object_changes);

use Data::Dumper;

no warnings 'experimental::smartmatch';

my $field_dict = {
    type_code => 'тип',
    offer_type_code => 'тип предложения',
    state_code => 'стадия',
    house_num => 'номер дома',
    house_type_id => 'материал',
    ap_num => 'номер квартиры',
    ap_scheme_id => 'планировка',
    rooms_count => 'кол-во комнат',
    rooms_offer_count => 'кол-во предлагаемых комнат',
    room_scheme_id => 'комнаты',
    floor => 'этаж',
    floors_count => 'всего этажей',
    levels_count => 'кол-во уровней',
    condition_id => 'состояние',
    balcony_id => 'балкон',
    bathroom_id => 'сан. узел',
    square_total => 'общая площадь',
    square_living => 'жилая площадь',
    square_kitchen => 'площадь кухни',
    square_land => 'площадь участка',
    square_land_type => 'тип площади',
    description => 'описание',
    source_media_id => 'источник',
    source_media_text => 'текст источника',
    owner_phones => 'телефон собственника',
    owner_price => 'цена собственника',
    work_info => 'рабочая информация',
    agent_id => 'агент',
    agency_price => 'цена агенства',
    price => 'цена',
    export_media => 'экспорт',
    rent_type => 'тип аренды',
    lease_deposite_id => 'залог',
    district => 'район',
    poi => 'ориентир',
    address => 'адрес',
    locality => 'город',
};

my $val_dict = {};

# ap_schemes:
my $iter = Rplus::Model::DictApScheme::Manager->get_objects_iterator(query => [delete_date => undef]);
while (my $x = $iter->next) {
    $val_dict->{ap_scheme_id}->{$x->id} = $x->name;
}

# balconies:
$iter = Rplus::Model::DictBalcony::Manager->get_objects_iterator(query => [delete_date => undef]);
while (my $x = $iter->next) {
  $val_dict->{balcony_id}->{$x->id} = $x->name;
}

# bathrooms:
$iter = Rplus::Model::DictBathroom::Manager->get_objects_iterator(query => [delete_date => undef]);
while (my $x = $iter->next) {
    $val_dict->{bathroom_id}->{$x->id} = $x->name;
}

# conditions:
$iter = Rplus::Model::DictCondition::Manager->get_objects_iterator(query => [delete_date => undef]);
while (my $x = $iter->next) {
    $val_dict->{condition_id}->{$x->id} = $x->name;
}

# house_types:
$iter = Rplus::Model::DictHouseType::Manager->get_objects_iterator(query => [delete_date => undef]);
while (my $x = $iter->next) {
    $val_dict->{house_type_id}->{$x->id} = $x->name;
}

# room_schemes:
$iter = Rplus::Model::DictRoomScheme::Manager->get_objects_iterator(query => [delete_date => undef]);
while (my $x = $iter->next) {
    $val_dict->{room_scheme_id}->{$x->id} = $x->name;
}

# media:
$iter = Rplus::Model::Media::Manager->get_objects_iterator(query => [delete_date => undef]);
while (my $x = $iter->next) {
    $val_dict->{media}->{$x->id} = $x->name;
}

# realty_types:
$iter = Rplus::Model::RealtyType::Manager->get_objects_iterator();
while (my $x = $iter->next) {
    $val_dict->{type_code}->{$x->id} = $x->name;
}

# realty_states:
$iter = Rplus::Model::RealtyState::Manager->get_objects_iterator();
while (my $x = $iter->next) {
    $val_dict->{state_code}->{$x->id} = $x->name;
}

# realty_offer_types:
$iter = Rplus::Model::RealtyOfferType::Manager->get_objects_iterator();
while (my $x = $iter->next) {
    $val_dict->{offer_type_code}->{$x->id} = $x->name;
}


sub put_record {
    my ($acc_id, $user_id, $type, $object_type, $object_id, $record, $metadata) = @_;
    my $realty = Rplus::Model::HistoryRecord->new(
        account_id => $acc_id,
        user_id => $user_id,
        type => $type,
        object_type => $object_type,
        object_id => $object_id,
        record => $record,
        metadata => $metadata ? encode_json($metadata) : undef,
    );
    $realty->save;
}

sub realty_record {     # add, change, update
    my ($acc_id, $user_id, $type, $realty, $new_data) = @_;

    if ($type eq 'like_it') {             # объект добавлен
        put_record($acc_id, $user_id, $type, 'realty', $realty->id, '' );
    } elsif ($type eq 'add') {            # объект добавлен
        put_record($acc_id, $user_id, $type, 'realty', $realty->id, '' , {
            owner_price => $realty->owner_price
        });
    } elsif ($type eq 'add_media') {      # объект найден в одном из источников
        put_record($acc_id, $user_id, $type, 'realty', $realty->id, 'источник ' . $val_dict->{media}->{$realty->source_media_id} );
    } elsif ($type eq 'update') {         # объект изменен пользователем
        my $ch_set = get_object_changes($realty, $new_data);
        if (%{$ch_set}) {
            my $t = changeset_to_string($ch_set);
            put_record($acc_id, $user_id, $type, 'realty', $realty->id, $t, $ch_set);
        }
    } elsif ($type eq 'update_media') {     # объект найден в одном из источников и будет обновлен
        my $ch_set = get_object_changes($realty, $new_data);
        if (%{$ch_set}) {
            my $t = changeset_to_string($ch_set);
            put_record($acc_id, $user_id, $type, 'realty', $realty->id, $t, $ch_set);
        }
    }
}

sub client_record {
    my ($acc_id, $user_id, $type, $client, $new_data) = @_;

    if ($type eq 'like_it') {             # объект добавлен
        put_record($acc_id, $user_id, $type, 'client', $client->id, '' );
    } elsif ($type eq 'add') {             # объект добавлен
        put_record($acc_id, $user_id, $type, 'client', $client->id, '' );
    } elsif ($type eq 'update') {     # объект изменен пользователем
        my $ch_set = get_object_changes($client, $new_data);
        if (%{$ch_set}) {
            my $t = changeset_to_string($ch_set);
            put_record($acc_id, $user_id, $type, 'client', $client->id, $t);
        }
    } elsif ($type eq 'delete') {     # объект изменен пользователем
        put_record($acc_id, $user_id, $type, 'client', $client->id, '' );
    }
}

sub subscription_record {
    my ($acc_id, $user_id, $type, $subscription, $new_data, $record) = @_;

    if ($type eq 'add') {             # объект добавлен
        put_record($acc_id, $user_id, $type, 'subscription', $subscription->id, $record);
    } elsif ($type eq 'update') {     # объект изменен пользователем
        my $ch_set = get_object_changes($subscription, $new_data);
        if (%{$ch_set}) {
            my $t = changeset_to_string($ch_set);
            put_record($acc_id, $user_id, $type, 'subscription', $subscription->id, $t);
        }
    } elsif ($type eq 'delete') {
        put_record($acc_id, $user_id, $type, 'subscription', $subscription->id, $record);
    } elsif ($type eq 'processing') {  # заявка обработана для отправки СМС
        # заявка обработана: СМС отправлено Х
    }
}

sub notification_record {
    my ($acc_id, $user_id, $type, $object, $record) = @_;

    if ($type eq 'sms_send') {             # объект добавлен
        put_record($acc_id, $user_id, $type, 'notification', $object->id, $record);
    } elsif ($type eq 'sms_enqueued') {     # объект изменен пользователем
        put_record($acc_id, $user_id, $type, 'notification', $object->id, $record);
    } elsif ($type eq 'email_send') {
        put_record($acc_id, $user_id, $type, 'notification', undef, $record);
    }
}

sub mediator_record {
    my ($acc_id, $user_id, $type, $object, $new_data) = @_;

    if ($type eq 'add') {             # объект добавлен
        put_record($acc_id, $user_id, $type, 'mediator', $object->id, '' );
    } elsif ($type eq 'add_company') {             # объект добавлен
        put_record($acc_id, $user_id, $type, 'mediator_company', $object->id, '' );
    } elsif ($type eq 'update') {     # объект изменен пользователем
        my $ch_set = get_object_changes($object, $new_data);
        if (%{$ch_set}) {
            my $t = changeset_to_string($ch_set);
            put_record($acc_id, $user_id, $type, 'mediator', $object->id, $t);
        }
    } elsif ($type eq 'update_company') {     # объект изменен пользователем
        my $ch_set = get_object_changes($object, $new_data);
        if (%{$ch_set}) {
            my $t = changeset_to_string($ch_set);
            put_record($acc_id, $user_id, $type, 'mediator_company', $object->id, $t);
        }
    } elsif ($type eq 'delete') {
        put_record($acc_id, $user_id, $type, 'mediator', $object->id, '' );
    } elsif ($type eq 'delete_company') {
        put_record($acc_id, $user_id, $type, 'mediator_company', $object->id, '' );
    }
}

sub task_record {
    my ($acc_id, $user_id, $type, $task, $new_data) = @_;

    if ($type eq 'add') {
        put_record($acc_id, $user_id, $type, 'task', $task->id, '' );
    } elsif ($type eq 'update') {
        my $ch_set = get_object_changes($task, $new_data);
        if (%{$ch_set}) {
            my $t = changeset_to_string($ch_set);
            put_record($acc_id, $user_id, $type, 'task', $task->id, $t);
        }
    }
}

sub changeset_to_string {
    my ($changeset) = @_;
    my @records;

    foreach my $key (keys %{$changeset}) {
        my $field = $key;
        $field = $field_dict->{$field} if $field_dict->{$field};

        if (ref($changeset->{$key}) eq 'HASH') {    # add rem

            my $ts = $field . ', ';

            my $ta = $changeset->{$key}->{add};
            if (@{$ta}) {
                $ts .= 'добавлено: ' . join(', ', @{$ta}) . '; ';
            }

            $ta = $changeset->{$key}->{rem};
            if (@{$ta}) {
                $ts .= 'удалено: ' . join(', ', @{$ta});
            }

            push @records, $ts;
        } else {
            my $ta = $changeset->{$key};
            my $v1 = $ta->[0];
            my $v2 = $ta->[1];

            $v1 = $val_dict->{$key}->{$v1} if $val_dict->{$key}->{$v1};
            $v2 = $val_dict->{$key}->{$v2} if $val_dict->{$key}->{$v2};

            push @records, $field . ': ' . $v1 . ' -> ' . $v2;
        }
    }

    return join '; ', @records;
}

sub get_object_changes {
    my ($object, $data) = @_;
    my $changes = {};

    foreach (keys %{$data}) {
        if (ref($object->$_) eq 'ARRAY') {

            my $l_ch = list_changes(\@{$object->$_}, $data->{$_});
            unless ($l_ch->{empty}) {
                $changes->{$_} = $l_ch;
            }
        } elsif ($_ eq 'multylisting') {    # костыль, надо что-то сделать с типом поля
            $data->{$_} = 0 unless defined $data->{$_};
            if ($object->$_ != $data->{$_}) {
                $changes->{$_} = [$object->$_, $data->{$_}];
            }
        } else {
            if ($object->$_ ne $data->{$_}) {
                $changes->{$_} = [$object->$_, $data->{$_}];
            }
        }
    }

    say Dumper $changes;

    return $changes;
}

sub list_changes {
    my ($a1, $a2) = @_;

    my $changes = {
        add => [],
        rem => [],
        empty => 1
    };
    my @t1 = @{$a1};
    my @t2 = @{$a2};

    foreach (@t2) {
        unless ($_ ~~ @t1) {    # элемент добавлен
            push @{$changes->{add}}, $_;
            $changes->{empty} = 0;
        }
    }
    foreach (@t1) {
        unless ($_ ~~ @t2) {    # элемент удален
            push @{$changes->{rem}}, $_;
            $changes->{empty} = 0;
        }
    }

    return $changes;
}

1;

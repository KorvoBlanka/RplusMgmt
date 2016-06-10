package RplusMgmt::Controller::Export::Present;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use Mojo::Util qw(trim);
use JSON;
use File::Temp qw(tmpnam);
use RTF::Writer;

sub index {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'present', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    my $meta = from_json($media->metadata);

    my $offer_type_code = $self->param('offer_type_code');
    my $realty_types = $self->param('realty_types');

    my $add_description_words = 5;
    my $conf_phones = '';
    my $agent_phone = 0;

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $e_opt = from_json($options->{options})->{'export'};
        $conf_phones = $e_opt->{'present-phones'} ? trim($e_opt->{'present-phones'}) : '';
        $agent_phone = 1 if $e_opt->{'present-agent-phone'};
        $add_description_words = $e_opt->{'present-descr'} ? $e_opt->{'present-descr'} * 1 : 5;
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my $file = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    {
        my $rtf = RTF::Writer->new_to_file($file);
        $rtf->prolog('charset' => 'ansicpg1251', colors => [undef, [255,0,0], [0,0,255], [255,255,0]]);

        my @landmarks = sort { ($a->name =~ s/^\((\d+)\).+$/$1/r || '100') <=> ($b->name =~ s/^\((\d+)\).+$/$1/r || 100) } @{Rplus::Model::Landmark::Manager->get_objects(query => [type => 'present', delete_date => undef])};
        push @landmarks, undef;

        my $_format_sum = sub {
            my $sum = shift;

            my ($m, $ths) = (($sum - $sum%1000)/1000, $sum%1000);
            my $human_sum;
            $human_sum = "$m млн." if $m;
            $human_sum .= ($m ? ' ' : '')."$ths тыс." if $ths;

            return $human_sum;
        };

        my $P = $meta->{'params'};

        # Комнаты
        if ($realty_types =~ /rooms/) {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        offer_type_code => $offer_type_code,
                        'type.category_code' => 'room',
                        export_media => {'&&' => $media->id},
                        account_id => $acc_id,
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address',
                    with_objects => ['sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        if ($l) {
                            $title = "Комнаты. ".($l->name =~ s/^\(\d+\)\s+//r);
                        } else {
                            $title = "Комнаты. Остальное";
                        }
                    }

                    my $location;
                    if ($realty->address) {
                        $location = $realty->address;
                        if ($realty->district && $location !~ /[()]/) {
                            $location .= ' ('.$realty->district.')';
                        }
                        $location .= '.';
                    }

                    my $type = 'Комн.'.($realty->rooms_count ? ' в '.$realty->rooms_count.'-комн.' : '');

                    my @digest;
                    push @digest, ($P->{'dict'}->{'ap_schemes'}->{$realty->ap_scheme_id} || $realty->ap_scheme->name) if $realty->ap_scheme_id;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, ($realty->floor || '?').'/'.($realty->floors_count || '?') if $realty->floor || $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    if ($add_description_words && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($add_description_words - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $conf_phones;
                    if ($agent_phone == 1 && $realty->agent) {
                        my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        # Малосемейки
        if ($realty_types =~ /apartments_small/) {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        offer_type_code => $offer_type_code,
                        type_code => 'apartment_small',
                        export_media => {'&&' => $media->id},
                        account_id => $acc_id,
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address',
                    with_objects => ['sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        if ($l) {
                            $title = "Малосемейки. ".($l->name =~ s/^\(\d+\)\s+//r);
                        } else {
                            $title = "Малосемейки. Остальное";
                        }
                    }

                    my $location;
                    if ($realty->address) {
                        $location = $realty->address;
                        if ($realty->district && $location !~ /[()]/) {
                            $location .= ' ('.$realty->district.')';
                        }
                        $location .= '.';
                    }

                    my $type = 'Малосем.';

                    my @digest;
                    push @digest, ($P->{'dict'}->{'ap_schemes'}->{$realty->ap_scheme_id} || $realty->ap_scheme->name) if $realty->ap_scheme_id;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, ($realty->floor || '?').'/'.($realty->floors_count || '?') if $realty->floor || $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    if ($add_description_words && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($add_description_words - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $conf_phones;
                    if ($agent_phone == 1 && $realty->agent) {
                        my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        # Квартиры (кроме малосемеек)
        if ($realty_types =~ /apartments/) {

            for my $xrc ((1..4), undef) {
                my %R;
                for my $l (@landmarks) {
                    my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                        query => [
                            offer_type_code => $offer_type_code,
                            'type.category_code' => 'apartment',
                            '!type_code' => 'apartment_small',
                            ($xrc ? (rooms_count => $xrc) : (rooms_count => {gt => 4})),
                            export_media => {'&&' => $media->id},
                            account_id => $acc_id,
                            ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                        ],
                        sort_by => 'address',
                        with_objects => ['sublandmark', 'type', 'agent'],
                    );
                    my ($title, @body);
                    while (my $realty = $iter->next) {
                        next if $R{$realty->id};
                        $R{$realty->id} = 1;
                        if (!$title) {
                            if ($l) {
                                $title = ($xrc ? "${xrc}-комнатные" : 'Многокомнатные').". ".($l->name =~ s/^\(\d+\)\s+//r);
                            } else {
                                $title = ($xrc ? "${xrc}-комнатные" : 'Многокомнатные').". Остальное";
                            }
                        }

                        my $location;
                        if ($realty->address) {
                            $location = $realty->address;
                            if ($realty->district && $location !~ /[()]/) {
                                $location .= ' ('.$realty->district.')';
                            }
                            $location .= '.';
                        }

                        my $type = ($realty->rooms_count || '?')."-комн.";

                        my @digest;
                        push @digest, ($P->{'dict'}->{'ap_schemes'}->{$realty->ap_scheme_id} || $realty->ap_scheme->name) if $realty->ap_scheme_id;
                        push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                        push @digest, ($realty->floor || '?').'/'.($realty->floors_count || '?') if $realty->floor || $realty->floors_count;
                        push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                        push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                        push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                        push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                        push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                        if ($add_description_words && $realty->description) {
                            my $c = 0;
                            my @desc;
                            for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                                my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                                if ($cc <= ($add_description_words - $c)) {
                                    push @desc, $x;
                                    $c += $cc;
                                }
                            }
                            push @digest, join(', ', @desc);
                        }
                        my $digest = join(', ', @digest);

                        my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                        my $phones = $conf_phones;
                        if ($agent_phone == 1 && $realty->agent) {
                            my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                            $phones =  $x . ', ' . $phones;
                        }

                        push @body, [\'\fi400\b', $location.' '] if $location;
                        push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                        push @body, "\n";
                    }

                    if ($title) {
                        $rtf->paragraph(\'\sa400\qc\b', $title);
                        $rtf->paragraph(\'\sa400', @body);
                    }
                }
            }
        }

        # Дома
        if ($realty_types =~ /houses/) {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        offer_type_code => $offer_type_code,
                        'type.category_code' => 'house',
                        export_media => {'&&' => $media->id},
                        account_id => $acc_id,
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address',
                    with_objects => ['sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        if ($l) {
                            $title = "Дома. ".($l->name =~ s/^\(\d+\)\s+//r);
                        } else {
                            $title = "Дома. Остальное";
                        }
                    }

                    my $location;
                    if ($realty->address) {
                        $location = $realty->address;
                        if ($realty->district && $location !~ /[()]/) {
                            $location .= ' ('.$realty->district.')';
                        }
                        $location .= '.';
                    }

                    my $type = $realty->type->name;

                    my @digest;
                    push @digest, $realty->rooms_count.'-комн.' if $realty->rooms_count;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, $realty->floors_count.' эт.' if $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    push @digest, $realty->square_land.' '.(($realty->square_land_type || 'ar') eq 'hectare' ? 'га.' : 'сот.') if $realty->square_land;
                    if ($add_description_words && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($add_description_words - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $conf_phones;
                    if ($agent_phone == 1 && $realty->agent) {
                        my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        if ($realty_types =~ /lands/) {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        offer_type_code => $offer_type_code,
                        'type.category_code' => 'land',
                        export_media => {'&&' => $media->id},
                        account_id => $acc_id,
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address',
                    with_objects => ['sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        $title = "Дачи. Участки.";
                    }

                    my $location;
                    if ($realty->address) {
                        $location = $realty->address;
                        if ($realty->district && $location !~ /[()]/) {
                            $location .= ' ('.$realty->district.')';
                        }
                        $location .= '.';
                    }

                    my $type = $realty->type->name;

                    my @digest;
                    push @digest, $realty->rooms_count.'-комн.' if $realty->rooms_count;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, $realty->floors_count.' эт.' if $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    push @digest, $realty->square_land.' '.(($realty->square_land_type || 'ar') eq 'hectare' ? 'га.' : 'сот.') if $realty->square_land;
                    if ($add_description_words && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($add_description_words - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $conf_phones;
                    if ($agent_phone == 1 && $realty->agent) {
                        my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        if ($realty_types =~ /commercials/) {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        offer_type_code => $offer_type_code,
                        'type.category_code' => ['commercial', 'commersial',],
                        export_media => {'&&' => $media->id},
                        account_id => $acc_id,
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address',
                    with_objects => ['sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        $title = "Коммерческая недвижимость";
                        #given ($realty->type_code) {
                        #    when ('market_place') {
                        #        $title = "Торговые площади";
                        #    }
                        #    when ('office') {
                        #        $title = "Офисные помещения";
                        #    }
                        #    when ('office_place') {
                        #        $title = "Офисные помещения";
                        #    }
                        #    when ('building') {
                        #        $title = "Здания";
                        #    }
                        #    when ('service_place') {
                        #        $title = "Помещения под сферу услуг";
                        #    }
                        #    when ('autoservice_place') {
                        #        $title = "Площади под автобизнес";
                        #    }
                        #    when ('gpurpose_place') {
                        #        $title = "Разные объекты";
                        #    }
                        #    when ('production_place') {
                        #        $title = "Площади под производство";
                        #    }
                        #    when ('warehouse_place') {
                        #        $title = "Склады. Участки.";
                        #    }
                        #}
                    }

                    my $location;
                    if ($realty->address) {
                        $location = $realty->address;
                        if ($realty->district && $location !~ /[()]/) {
                            $location .= ' ('.$realty->district.')';
                        }
                        $location .= '.';
                    }

                    my $type = $realty->type->name;

                    my @digest;
                    push @digest, $realty->rooms_count.'-комн.' if $realty->rooms_count;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, $realty->floors_count.' эт.' if $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    push @digest, $realty->square_land.' '.(($realty->square_land_type || 'ar') eq 'hectare' ? 'га.' : 'сот.') if $realty->square_land;
                    if ($add_description_words && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($add_description_words - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $conf_phones;
                    if ($agent_phone == 1 && $realty->agent) {
                        my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        # Дома
        if ($realty_types =~ /garages/) {
            my %R;
            for my $l (@landmarks) {
                my $iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                    query => [
                        offer_type_code => $offer_type_code,
                        type_code => 'garage',
                        export_media => {'&&' => $media->id},
                        account_id => $acc_id,
                        ($l ? \("t1.landmarks && '{".$l->id."}'") : \("NOT (t1.landmarks && ARRAY(SELECT L.id FROM landmarks L WHERE L.type = 'present' AND L.delete_date IS NULL))")),
                    ],
                    sort_by => 'address',
                    with_objects => ['sublandmark', 'type', 'agent'],
                );
                my ($title, @body);
                while (my $realty = $iter->next) {
                    next if $R{$realty->id};
                    $R{$realty->id} = 1;
                    if (!$title) {
                        $title = "Гаражи";
                        #given ($realty->type_code) {
                        #    when ('market_place') {
                        #        $title = "Торговые площади";
                        #    }
                        #    when ('office') {
                        #        $title = "Офисные помещения";
                        #    }
                        #    when ('office_place') {
                        #        $title = "Офисные помещения";
                        #    }
                        #    when ('building') {
                        #        $title = "Здания";
                        #    }
                        #    when ('service_place') {
                        #        $title = "Помещения под сферу услуг";
                        #    }
                        #    when ('autoservice_place') {
                        #        $title = "Площади под автобизнес";
                        #    }
                        #    when ('gpurpose_place') {
                        #        $title = "Разные объекты";
                        #    }
                        #    when ('production_place') {
                        #        $title = "Площади под производство";
                        #    }
                        #    when ('warehouse_place') {
                        #        $title = "Склады. Участки.";
                        #    }
                        #}
                    }

                    my $location;
                    if ($realty->address) {
                        $location = $realty->address;
                        if ($realty->district && $location !~ /[()]/) {
                            $location .= ' ('.$realty->district.')';
                        }
                        $location .= '.';
                    }

                    my $type = $realty->type->name;

                    my @digest;
                    push @digest, $realty->rooms_count.'-комн.' if $realty->rooms_count;
                    push @digest, ($P->{'dict'}->{'house_types'}->{$realty->house_type_id} || $realty->house_type->name) if $realty->house_type_id;
                    push @digest, $realty->floors_count.' эт.' if $realty->floors_count;
                    push @digest, ($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id} || $realty->room_scheme->name) if $realty->room_scheme_id;
                    push @digest, ($P->{'dict'}->{'conditions'}->{$realty->condition_id} || $realty->condition->name) if $realty->condition_id;
                    push @digest, $realty->square_total.($realty->square_living && $realty->square_kitchen ? '/'.$realty->square_living.'/'.$realty->square_kitchen : ' кв.м.') if $realty->square_total;
                    push @digest, ($P->{'dict'}->{'balconies'}->{$realty->balcony_id} || $realty->balcony->name) if $realty->balcony_id;
                    push @digest, ($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id} || $realty->bathroom->name) if $realty->bathroom_id;
                    push @digest, $realty->square_land.' '.(($realty->square_land_type || 'ar') eq 'hectare' ? 'га.' : 'сот.') if $realty->square_land;
                    if ($add_description_words && $realty->description) {
                        my $c = 0;
                        my @desc;
                        for my $x (grep { $_ } trim(split(/,|\n/, $realty->description))) { # Phrases
                            my $cc = scalar(grep { $_ } (split /\W/, $x)); # Num words of phrase
                            if ($cc <= ($add_description_words - $c)) {
                                push @desc, $x;
                                $c += $cc;
                            }
                        }
                        push @digest, join(', ', @desc);
                    }
                    my $digest = join(', ', @digest);

                    my $price = $_format_sum->($realty->price).' руб.' if $realty->price;
                    my $phones = $conf_phones;
                    if ($agent_phone == 1 && $realty->agent) {
                        my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                        $phones =  $x . ', ' . $phones;
                    }

                    push @body, [\'\fi400\b', $location.' '] if $location;
                    push @body, join(' ', $type, ($digest ? "($digest)" : ()), ($price || ()), $phones);
                    push @body, "\n";
                }

                if ($title) {
                    $rtf->paragraph(\'\sa400\qc\b', $title);
                    $rtf->paragraph(\'\sa400', @body);
                }
            }
        }

        $rtf->close;
    }

    $self->res->headers->content_disposition('attachment; filename=present.rtf;');
    $self->res->content->asset(Mojo::Asset::File->new(path => $file), Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;

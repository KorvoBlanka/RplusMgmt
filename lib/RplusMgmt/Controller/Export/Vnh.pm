package RplusMgmt::Controller::Export::Vnh;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use Spreadsheet::WriteExcel;
use JSON;

sub index {
    my $self = shift;

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'vnh', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    my $meta = from_json($media->metadata);

    my $offer_type_code = $self->param('offer_type_code');
    my $realty_types = $self->param('realty_types');

    my $company = '';
    my $conf_phones = '';
    my $agent_phone = 0;

    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'export')->load();
    if ($rt_param) {
        my $config = from_json($rt_param->{value});
        $conf_phones = $config->{'vnh-phones'} ? trim($config->{'vnh-phones'}) : '';
        $agent_phone = 1 if $config->{'vnh-agent-phone'} eq 'true';
        $company = $config->{'vnh-company'} ? trim($config->{'vnh-company'}) : '';
    }

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my $file = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);


    {
        my $workbook = Spreadsheet::WriteExcel->new($file);

        my $P = $meta->{'params'};

        # Раздел: Квартиры
        # Включает в себя комнаты + квартиры
        if ($realty_types =~ /apartments_rooms/) {
            my $worksheet = $workbook->add_worksheet("Квартиры");

            # Заголовок листа
            my $header_fmt1 = $workbook->add_format(border => 1, bold => 1, bg_color => 'silver', valign  => 'vcenter', align => 'center', text_wrap => 1);
            my $header_fmt2 = $workbook->add_format(); $header_fmt2->copy($header_fmt1);
            my $header = {
                'A1:A2' => { text => "Тип", width => 5 },
                'B1:B2' => { text => "Кол.\nкомн." },
                'C1:C2' => { text => "Р-он" },
                'D1:D2' => { text => "Подрайон", width => 12 },
                'E1:E2' => { text => "Расположение", width => 22 },
                'F1:F2' => { text => "Этаж" },
                'G1:G2' => { text => "Тип" },
                'H1:H2' => { text => "План." },
                'I1:K1' => { text => "Площадь" },
                'I2' => { text => "общ."},
                'J2' => { text => "жил."},
                'K2' => { text => "кух."},
                'L1:L2' => { text => "Тип\nкомн." },
                'M1:M2' => { text => "С/у" },
                'N1:N2' => { text => "Л/Б" },
                'O1:O2' => { text => "Тел." },
                'P1:P2' => { text => "Сост.\nкварт." },
                'Q1:Q2' => { text => "Цена\nтыс. руб." },
                'R1:R2' => { text => "Телефон", width => 15 },
                'S1:S2' => { text => "Фирма", width => 10 },
                'T1:T2' => { text => "ВНХ" }
            };
            for my $x (keys %$header) {
                if ($x =~ /^(\S)\d$/) {
                    $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt1);
                    $worksheet->set_column("$1:$1", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
                } elsif ($x =~ /^(\S)(\d)\:(\S)(\d)$/) {
                    $worksheet->merge_range($x, $header->{$x}->{'text'}, $header_fmt2);
                    $worksheet->set_column("$1:$3", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
                }
            }

            my $txt_fmt = $workbook->add_format(num_format => '@');

            # Выборка объектов недвижимости
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => $offer_type_code,
                    'type.category_code' => ['room', 'apartment'],
                    export_media => {'&&' => $media->id},
                ],
                sort_by => 'address_object.expanded_name',
                with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
            );
            my $row_num = 2;
            while(my $realty = $realty_iter->next) {
                my $location = '';
                if ($realty->address_object_id) {
                    my $addrobj = $realty->address_object;
                    my $meta = from_json($addrobj->metadata);
                    $location = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                    if ($realty->sublandmark_id) {
                        $location .= ' ('.$realty->sublandmark->name.')';
                    }
                }
                my ($area, $subarea);
                if (@{$realty->landmarks}) {
                    $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_area', delete_date => undef], limit => 1)->[0];
                    $subarea = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_subarea', delete_date => undef], limit => 1)->[0];
                }

                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }

                my $row = [
                    $P->{'realty_categories'}->{$realty->type->category_code} || '',
                    $realty->rooms_count || '',
                    $area ? $area->name : '',
                    $subarea ? $subarea->name : '',
                    $location,
                    $realty->floor || $realty->floors_count ? ($realty->floor || '?').'/'.($realty->floors_count || '?') : '',
                    $realty->house_type_id ? (($P->{'dict'}->{'house_types'}->{$realty->house_type_id}) // '') : '',
                    $realty->ap_scheme_id ? (($P->{'dict'}->{'ap_schemes'}->{$realty->ap_scheme_id}) // '') : '',
                    $realty->square_total,
                    $realty->square_living,
                    $realty->square_kitchen,
                    $realty->room_scheme_id ? (($P->{'dict'}->{'room_schemes'}->{$realty->room_scheme_id}) // '') : '',
                    $realty->bathroom_id ? (($P->{'dict'}->{'bathrooms'}->{$realty->bathroom_id}) // '') : '',
                    $realty->balcony_id ? (($P->{'dict'}->{'balconies'}->{$realty->balcony_id}) // '') : '',
                    '+',
                    $realty->condition_id ? (($P->{'dict'}->{'conditions'}->{$realty->condition_id}) // '') : '',
                    $realty->price,
                    $phones,
                    $company,
                    '+',
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    if ($col_num == 5) {
                        $worksheet->write_string($row_num, $col_num, $row->[$col_num], $txt_fmt);
                    } else {
                        $worksheet->write($row_num, $col_num, $row->[$col_num]);
                    }
                }
                $row_num++;
            }
        }

        # Раздел: Частные дома и коттеджи
        # Включает в себя дома
        if ($realty_types =~ /houses/)  {
            my $worksheet = $workbook->add_worksheet("Частные дома и коттеджи");

            # Заголовок листа
            my $header_fmt1 = $workbook->add_format(border => 1, bold => 1, bg_color => 'silver', valign  => 'vcenter', align => 'center', text_wrap => 1);
            my $header_fmt2 = $workbook->add_format(); $header_fmt2->copy($header_fmt1);
            my $header = {
                'A1' => { text => "Р-он" },
                'B1' => { text => "Подрайон", width => 12 },
                'C1' => { text => "Расположение", width => 22 },
                'D1' => { text => "Эт" },
                'E1' => { text => "Тип" },
                'F1' => { text => "Уч-к,с." },
                'G1' => { text => "Площадь дома, кв.м." },
                'H1' => { text => "Кол. ком." },
                'I1' => { text => "Дополнительные сведения" },
                'J1' => { text => "Цена\nтыс. руб." },
                'K1' => { text => "Телефон", width => 15 },
                'L1' => { text => "Фирма", width => 10 },
                'M1' => { text => "ВНХ" }
            };
            for my $x (keys %$header) {
                if ($x =~ /^(\S)\d$/) {
                    $worksheet->write_string($x, $header->{$x}->{'text'}, $header_fmt1);
                    $worksheet->set_column("$1:$1", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
                } elsif ($x =~ /^(\S)(\d)\:(\S)(\d)$/) {
                    $worksheet->merge_range($x, $header->{$x}->{'text'}, $header_fmt2);
                    $worksheet->set_column("$1:$3", $header->{$x}->{'width'}) if exists $header->{$x}->{'width'};
                }
            }

            my $txt_fmt = $workbook->add_format(num_format => '@');

            # Выборка частных домов и коттеджей
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    offer_type_code => $offer_type_code,
                    'type.category_code' => 'house',
                    export_media => {'&&' => $media->id},
                ],
                sort_by => 'address_object.expanded_name',
                with_objects => ['address_object', 'sublandmark', 'type', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $location = '';
                if ($realty->address_object_id) {
                    my $addrobj = $realty->address_object;
                    my $meta = from_json($addrobj->metadata);
                    $location = $addrobj->name.($addrobj->short_type ne 'ул' ? ' '.$addrobj->short_type : '');
                    if ($realty->sublandmark_id) {
                        $location .= ' ('.$realty->sublandmark->name.')';
                    }
                }
                my ($area, $subarea);
                if (@{$realty->landmarks}) {
                    $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_area', delete_date => undef], limit => 1)->[0];
                    $subarea = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'vnh_subarea', delete_date => undef], limit => 1)->[0];
                }
                my $phones = $conf_phones;
                if ($agent_phone == 1 && $realty->agent) {
                    my $x = $realty->agent->public_phone_num || $realty->agent->phone_num;
                    $phones =  $x . ', ' . $phones;
                }
                my $row = [
                    $area ? $area->name : '',
                    $subarea ? $subarea->name : '',
                    $location,
                    $realty->floors_count // '',
                    $realty->house_type_id ? (($P->{'dict'}->{'house_types'}->{$realty->house_type_id}) // '') : '',
                    ($realty->square_land_type || '') eq 'ar' && $realty->square_land ? $realty->square_land : '',
                    $realty->square_total,
                    $realty->rooms_count // '',
                    $realty->description,
                    $realty->price,
                    $phones,
                    $company,
                    '+',
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    $worksheet->write($row_num, $col_num, $row->[$col_num]);
                }
                $row_num++;
            }
        }

        $workbook->close;
    }

    $self->res->headers->content_disposition('attachment; filename=vnh.xls;');
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;

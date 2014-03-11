package RplusMgmt::Controller::Export::Farpost;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Media;
use Rplus::Model::Media::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use Mojo::Util qw(trim);
use File::Temp qw(tmpnam);
use Spreadsheet::WriteExcel;
use JSON;

sub index {
    my $self = shift;

    return $self->render_not_found unless $self->req->method eq 'POST';
    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'export');

    my $media = Rplus::Model::Media::Manager->get_objects(query => [code => 'farpost', type => 'export', delete_date => undef])->[0];
    return $self->render_not_found unless $media;

    my $meta = from_json($media->metadata);

    my $phones = trim(scalar $self->param('phones'));

    $meta->{'params'}->{'phones'} = $phones;

    unlink($meta->{'prev_file'}) if $meta->{'prev_file'};
    my $file = tmpnam();
    $meta->{'prev_file'} = $file;

    $media->metadata(encode_json($meta));
    $media->save(changes_only => 1);

    {
        my $workbook = Spreadsheet::WriteExcel->new($file);

        my $P = $meta->{'params'};

        {
            my $worksheet = $workbook->add_worksheet("Лист1");

            # Заголовок листа
            my $header_fmt1 = $workbook->add_format(border => 1, bold => 0, bg_color => 'silver', valign  => 'vcenter', align => 'center', text_wrap => 1);
            my $header_fmt2 = $workbook->add_format(); $header_fmt2->copy($header_fmt1);
            my $header = {
                'A1' => { text => "Код сделки" },
                'B1' => { text => "Тип сделки", width => 15 },
                'C1' => { text => "Вид недвижимости", width => 15 },
                'D1' => { text => "Район", width => 22 },
                'E1' => { text => "Улица", width => 35 },
                'F1' => { text => "Номер дома" },
                'G1' => { text => "Количество комнат" },
                'H1' => { text => "Общая площадь" },
                'I1' => { text => "Этаж" },
                'J1' => { text => "Всего этажей" },
                'K1' => { text => "Состояние", width => 15 },
                'L1' => { text => "Срок аренды" },
                'M1' => { text => "Дополнительные платежи", widht => 20 },
                'N1' => { text => "Дополнительное описание", width => 25 },
                'O1' => { text => "Особые требования к съемщикам", width => 20 },
                'P1' => { text => "Цена (руб)" },
                'Q1' => { text => "Коммисия агенства", width => 15 },
                'R1' => { text => "Стоимость просмотра", width => 15 },
                'S1' => { text => "Ссылки на фотографии", width => 70 },
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
            my $txt_fmt2 = $workbook->add_format(); $txt_fmt2->set_text_wrap();

            # Выборка частных домов и коттеджей
            my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
                query => [
                    state_code => 'work',
                    export_media => {'&&' => $media->id},
                ],
                sort_by => 'address_object.expanded_name',
                require_objects => ['type', 'offer_type'],
                with_objects => ['address_object', 'sublandmark', 'condition', 'agent'],
            );
            my $row_num = 1;
            while(my $realty = $realty_iter->next) {
                my $area = Rplus::Model::Landmark::Manager->get_objects(query => [id => scalar($realty->landmarks), type => 'farpost', delete_date => undef], limit => 1)->[0] if @{$realty->landmarks};
                my $phones = $P->{'phones'} || '';
                if ($phones =~ /%agent\.phone_num%/ && $realty->agent_id) {
                    my $x = from_json($realty->agent->metadata)->{'public_phone_num'} || $realty->agent->phone_num;
                    $phones =~ s/%agent\.phone_num%/$x/;
                }
                my @photos = @{Rplus::Model::Photo::Manager->get_objects(query => [realty_id => $realty->id, delete_date => undef])};

                my $row = [
                    '',
                    $realty->offer_type->name,
                    $realty->type->name,
                    $area ? $area->name : '',
                    $realty->address_object ? $realty->address_object->name.($realty->address_object->short_type ne 'ул' ? ' '.$realty->address_object->short_type : '') : '',
                    $realty->house_num || '',
                    $realty->rooms_count || '',
                    $realty->square_total || '',
                    $realty->floor || '',
                    $realty->floors_count || '',
                    $realty->condition ? $realty->condition->name : '',
                    '',
                    '',
                    $realty->description,
                    '',
                    $realty->price * 1000,
                    '',
                    '',
                    @photos ? {type => 'photo_list', body => join("\n", map { $self->config->{'storage'}->{'url'}.'/photos/'.$_->realty_id.'/'.$_->filename } @photos)} : '',
                ];
                for my $col_num (0..(scalar(@$row)-1)) {
                    my $x = $row->[$col_num];
                    if (ref($x) eq 'HASH') {
                        if ($x->{'type'} eq 'photo_list') {
                            $worksheet->set_row($row_num, 60);
                            $worksheet->write_string($row_num, $col_num, $x->{'body'}, $txt_fmt2);
                        }
                    } else {
                        $worksheet->write($row_num, $col_num, $x);
                    }
                }
                $row_num++;
            }
        }

        $workbook->close;
    }

    $self->res->headers->content_disposition('attachment; filename=farpost.xls;');
    $self->res->content->asset(Mojo::Asset::File->new(path => $file));

    return $self->rendered(200);
}

1;

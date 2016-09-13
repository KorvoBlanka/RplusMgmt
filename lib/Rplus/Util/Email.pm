package Rplus::Util::Email;

use Rplus::Modern;

use Rplus::Model::Account::Manager;
use Rplus::Model::Photo::Manager;

use Rplus::Util::History qw(notification_record);
use Rplus::Util::Config;

use MIME::Lite;
use IPC::Open2;
use JSON;
use Net::SMTP::SSL;

use Exporter qw(import);

our @EXPORT_OK = qw(prepare_email_message send_email);

my $template_head = <<'END_MESSAGE';

<html lang="ru">
    <!-- BEGIN HEAD -->
    <head>
      <meta charset="utf-8"/>
    </head>
    <body>
        <div style="width="100%;">
END_MESSAGE

my $template_tail = '</div></body></html>';

sub prepare_email_message {
    my ($realty, $sender, $acc_id) = @_;
    my $r = $realty;

    my $app_config = Rplus::Util::Config::get_config();

    my $acc = Rplus::Model::Account::Manager->get_objects(query => [id => $acc_id])->[0];
    my $acc_name = $acc->name;

    my $contact_info = '';
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $opt = from_json($options->{options})->{'notifications'};
        $contact_info = $opt->{'contact_info'} ? $opt->{'contact_info'} : '';
    }

    my $no_photo_url =  '<%= $assets_url %>/img/no_user_image.gif';
    my $no_photo_big_url = '<%= $assets_url %>/img/no-photo-big.gif';

    my $sender_block = '';
    my $header_block = '';
    my $info_block = '';

    $sender_block .= '<hr>';

    my $use_sender_data = 0;
    my $user_photo = '';
    my $path = $app_config->{'storage'}->{'external'} . '/' . $acc_name;
    if ($sender->role eq 'manager' || $sender->role eq 'top') {
        if ($r->agent_id) {
            $use_sender_data = 0;
            $user_photo = $r->agent->photo_url;
        } else {
            $use_sender_data = 1;
            $user_photo = $sender->photo_url;
        }
    } else {
        $use_sender_data = 1;
        $user_photo = $sender->photo_url;
    }

    if ($user_photo) {
        my $photo_url = $path . $user_photo;
        $sender_block .= '<div style="width: 150px; padding: 10px; display: inline-block; float: left;">';
        $sender_block .= "<img style=\"width: 100%;\" src=\"$photo_url\">";
        $sender_block .= '</div>';
    } else {
        $sender_block .= '<div style="width: 150px; padding: 10px; display: inline-block; float: left;">';
        $sender_block .= "<img style=\"width: 100%;\" src=\"$no_photo_url\">";
        $sender_block .= '</div>';
    }

    if ($use_sender_data) {
        $sender_block .= '<div style="width: 350px; padding: 10px; padding-top: 30px; display: inline-block; float: left;">';
        $sender_block .= '<span>' . $contact_info . '</span>';
        $sender_block .= '<br>';
        $sender_block .= '<span>Агент:&nbsp;' . ($sender->public_name || $sender->name) . ', ' . ($sender->public_phone_num || $sender->phone_num) . '</span>';
        $sender_block .= '</div>';
    } else {
        $sender_block .= '<div style="width: 350px; padding: 10px; padding-top: 30px; display: inline-block; float: left;">';
        $sender_block .= '<span>' . $contact_info . '</span>';
        $sender_block .= '<br>';
        $sender_block .= '<span>Агент:&nbsp; ' . ($r->agent->public_name || $r->agent->name) . ', ' . ($r->agent->public_phone_num || $r->agent->phone_num) . '</span>';
        $sender_block .= '</div>';
    }
    $sender_block  .=  '<hr style="clear: both;">';


    $header_block  .=  '<strong>' . $r->type->name . '</strong>';
    $header_block  .=  '&nbsp;' . $r->rooms_count . 'к' if ($r->rooms_count);
    if ($r->address) {
        $header_block  .=  ', &nbsp;' . $r->address . '. ' . ($r->house_num ? $r->house_num : '') . ($r->district ? ' (' . $r->district . ')' : '');
    }


     if ($r->price) {
        $info_block  .=  '<br><span style="font-size: 20px;">Цена:&nbsp;<i style="color: #d9534f;">' . $r->price . ' тыс. руб.</i></span><br>';
    }

    if ($r->ap_scheme) {
        $info_block  .=  'Планировка:&nbsp;';
        $info_block  .=  $r->ap_scheme->metadata ? from_json($r->ap_scheme->metadata)->{description} : $r->ap_scheme->name;
        $info_block  .=  '<br>';
    }
    if ($r->house_type) {
        #push @digest, $r->house_type->metadata ? from_json($r->house_type->metadata)->{description} : $r->house_type->name;
        $info_block  .=  'Тип дома:&nbsp;';
        $info_block  .=  $r->house_type->name;
        $info_block  .=  '<br>';
    }
    if ($r->room_scheme) {
        #push @digest, $r->room_scheme->metadata ? from_json($r->room_scheme->metadata)->{description} : $r->room_scheme->name;
        $info_block  .=  'Комнаты:&nbsp;';
        $info_block  .=  $r->room_scheme->name;
        $info_block  .=  '<br>';
    }
    if ($r->rooms_count) {
        $info_block  .=  'Кол-во комнат: ';
        $info_block  .=  $r->rooms_count;
        $info_block  .=  '<br>';
    }
    if ($r->floor && $r->floors_count) {
        $info_block  .=  'Этаж:&nbsp;';
        $info_block  .=  $r->floor . '/' . $r->floors_count . ' эт.';
        $info_block  .=  '<br>';
    } elsif ($r->floor || $r->floors_count) {
        $info_block  .=  'Этаж:&nbsp;';
        $info_block  .=  $r->floor || $r->floors_count . ' эт.';
        $info_block  .=  '<br>';
    }
    if ($r->condition) {
        $info_block  .= 'Состояние:&nbsp;';
        #push @digest, $r->condition->metadata ? from_json($r->condition->metadata)->{description} : $r->condition->name;
        $info_block  .=  $r->condition->name;
        $info_block  .= '<br>';
    }
    if ($r->balcony) {
        $info_block  .= 'Балкон:&nbsp;';
        #push @digest, $r->balcony->metadata ? from_json($r->balcony->metadata)->{description} : $r->balcony->name;
        $info_block  .= $r->balcony->name;
        $info_block  .= '<br>';
    }
    if ($r->bathroom) {
        $info_block  .= 'Санузел:&nbsp;';
        #push @digest, $r->bathroom->metadata ? from_json($r->bathroom->metadata)->{description} : $r->bathroom->name;
        $info_block  .= $r->bathroom->name;
        $info_block  .= '<br>';
    }

    my @squares;
    {
        if ($r->square_total) {
            push @squares, $r->square_total;
        }
        if ($r->square_living) {
            push @squares, $r->square_living;
        }
        if ($r->square_kitchen) {
            push @squares, $r->square_kitchen;
        }
        if (scalar @squares) {
            $info_block  .= 'Площадь:&nbsp;';
            $info_block  .= ((join '/', @squares) . ' кв. м.');
            $info_block  .= '<br>';
        }
    }

    if ($r->square_land && $r->square_land_type) {
        $info_block  .= 'Земля:&nbsp;';
        $info_block  .= $r->square_land . ' ' . ($r->square_land_type eq 'ar' ? 'сот.' : 'га');
        $info_block  .= '<br>';
    }

    if ($r->description) {
        $info_block  .= '<br><br><span style="font-size: 20px;">Описание:</span>';
        $info_block  .= '<br>' . $r->description . '</br>';
    }

    my $message = $template_head;

    $message .= '<div style="">';
    $message .= $sender_block;
    $message .= '</div>';

    $message .= '<div style="font-size: 22px;">';
    $message .= $header_block;
    $message .= '</div>';

    $message .= '<div style="width: 65%; padding: 10px; display: inline-block; float: left;">';

    my $no_photo = 1;
    my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty->id, delete_date => undef], sort_by => 'is_main DESC, id ASC');
    while (my $photo = $photo_iter->next) {
        my $t = $photo->thumbnail_filename;
        $no_photo = 0;
        my $url = '';
        if ($t !~ /^http/) {
            $url = $app_config->{storage}->{external} . '/photos/';
        }
        $message .= "<img style=\"\" width=\"100%\" src=\"" . $url . "$t\">";
    }
    if ($no_photo) {
        $message .= "<img style=\"\" width=\"100%\" src=\"$no_photo_big_url\">";
    }
    $message .= '</div>';

    $message .= '<div style="width: 25%; padding: 10px; display: inline-block; float: left;">';
    $message .= $info_block;
    $message .= '</div>';


    $message .= $template_tail;
    return $message;
}


sub send_email {
    my ($to, $subject, $message, $acc_id) = @_;

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    my $config;
    if ($options) {
        $config = from_json($options->{options})->{'notifications'};
    } else {
        return 0;
    }

    my $from = $config->{'email-user'};

    my $msg = MIME::Lite->new(
                   From     => $from,
                   To       => $to,
                   Subject  => $subject,
                   Data     => $message
                   );
    $msg->attr("content-type" => "text/html; charset=UTF-8");
    #$msg->send('smtp', 'smtp.yandex.ru', AuthUser=>'info@rplusmgmt.com', AuthPass=>'ckj;ysqgfhjkm', Port => 587);

    my $port = 465;
    if ($config->{'email-port'} =~ /^(\d+)$/) {
      $port = $1;
    }

    my $smtp = Net::SMTP::SSL->new($config->{'email-smtp'}, Port => $port);
    if ($smtp) {
        $smtp->auth($config->{'email-user'}, $config->{'email-password'}); # or die "Can't authenticate:".$smtp->message();
        $smtp->mail($config->{'email-user'}); # or die "Error:".$smtp->message();
        $smtp->to($to); # or die "Error:".$smtp->message();
        $smtp->data(); # or die "Error:".$smtp->message();
        $smtp->datasend($msg->as_string); # or die "Error:".$smtp->message();
        $smtp->dataend(); # or die "Error:".$smtp->message();
        $smtp->quit(); # or die "Error:".$smtp->message();

        return 1;
    }

    return 0;
}

1;

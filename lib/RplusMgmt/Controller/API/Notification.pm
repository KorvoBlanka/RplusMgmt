package RplusMgmt::Controller::API::Notification;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;
use Rplus::Util::SMS;
use Rplus::Util::Email;


use Mojo::Base 'Mojolicious::Controller';

use Encode qw(decode encode);
use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;

no warnings 'experimental::smartmatch';

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

sub by_sms {
    my $self = shift;
    my $client_id = $self->param('client_id');
    my $realty_id = $self->param('realty_id');
    my $sms_text = '';
    my $status = 'not sent';

    my $client = Rplus::Model::Client::Manager->get_objects(query => [id => $client_id, delete_date => undef])->[0];

    my $realty = Rplus::Model::Realty::Manager->get_objects(
        query => [id => $realty_id,],
        with_objects => ['agent', 'type'],
    )->[0];

    my $acc_id = $self->session('account')->{id};
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    my $config;
    if ($options) {
        $config = from_json($options->{options})->{notifications};
    } else {
        return $self->render(json => {status => 'no config',});
    }

    my $sender = Rplus::Model::User::Manager->get_objects(query => [id => $self->stash('user')->{id}, delete_date => undef])->[0];

    # Prepare SMS for client
    if ($client->phone_num =~ /^9\d{9}$/) {
        # TODO: Add template settings
        my @parts;
        {
            push @parts, $realty->type->name;
            push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
            push @parts, $realty->locality.', '.$realty->address if $realty->address && $realty->locality;
            push @parts, $realty->district if $realty->district;
            push @parts, ($realty->floor || '?').'/'.($realty->floors_count || '?').' эт.' if $realty->floor || $realty->floors_count;
            push @parts, $realty->price.' тыс. руб.' if $realty->price;
            push @parts, $sender->public_name || $sender->name;
            push @parts, $sender->public_phone_num || $sender->phone_num;
        }
        my $sms_body = join(', ', @parts);
        $sms_text = 'Вы интересовались: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').($config->{'contact_info'} ? $config->{'contact_info'} : '');

        $status = Rplus::Util::SMS::send($self, $config, $acc_id, $client->phone_num, $sms_text);

        my $subscription_iter = Rplus::Model::Subscription::Manager->get_objects_iterator(query => [client_id => $client->id, delete_date => undef,]);
        while (my $subscription = $subscription_iter->next) {
            my $num_rows_updated = Rplus::Model::SubscriptionRealty::Manager->update_objects(
                set => {offered => 1},
                where => [realty_id => $realty->id, subscription_id => $subscription->id],
            );
        }
    }

    return $self->render(json => {status => $status, data => $config->{active},});
}

sub by_email {
    my $self = shift;
    my $client_id = $self->param('client_id');
    my $realty_id = $self->param('realty_id');
    my $email_text = '';
    my $status = 'not sent';

    my $client = Rplus::Model::Client::Manager->get_objects(query => [id => $client_id, delete_date => undef])->[0];

    my $realty = Rplus::Model::Realty::Manager->get_objects(
        query => [id => $realty_id,],
        with_objects => ['agent', 'type'],
    )->[0];

    my $acc_id = $self->session('account')->{id};
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    my $config;
    if ($options) {
        $config = from_json($options->{options})->{'notifications'};
    } else {
        return;
    }

    # Prepare email for client
    if ($client->email) {
        my @photos;
        my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty->id, delete_date => undef], sort_by => 'is_main DESC, id ASC');
        while (my $photo = $photo_iter->next) {
            push @photos, $photo->thumbnail_filename;
        }
        # TODO: Add template settings
        my $sender = Rplus::Model::User::Manager->get_objects(query => [id => $self->stash('user')->{id}, delete_date => undef])->[0];
        my $message = get_digest($self, $realty, \@photos, $config->{'contact_info'} ? $config->{'contact_info'} : '', $sender);

        $status = Rplus::Util::Email::send($self, $client->email, $message, $config);
    }

    return $self->render(json => {status => $status,});
}

sub get_digest {
    my ($c, $r, $photos, $contact_info, $sender) = @_;

    my $no_photo_url =  '<%= $assets_url %>/img/no_user_image.gif';
    my $no_photo_big_url = '<%= $assets_url %>/img/no-photo-big.gif';

    my $sender_block = '';
    my $header_block = '';
    my $info_block = '';

    $sender_block .= '<hr>';

    my $use_sender_data = 0;
    my $user_photo = '';
    my $path = $c->config->{'storage'}->{'external'} . '/' . $c->session('account')->{name};
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
    foreach(@$photos) {
        $message .= "<img style=\"\" width=\"100%\" src=\"" . $c->config->{storage}->{external} . '/photos/' . "$_\">";
    }
    unless (scalar @$photos) {
        $message .= "<img style=\"\" width=\"100%\" src=\"$no_photo_big_url\">";
    }
    $message .= '</div>';

    $message .= '<div style="width: 25%; padding: 10px; display: inline-block; float: left;">';
    $message .= $info_block;
    $message .= '</div>';


    $message .= $template_tail;
    return $message;
}

1;

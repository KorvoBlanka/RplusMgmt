package RplusMgmt::Controller::API::Notification;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;
use Rplus::Util::SMS;
use Rplus::Util::Email;

use Mojo::Base 'Mojolicious::Controller';

use Encode qw(decode encode);
use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;

use Data::Dumper;

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
        with_objects => ['address_object', 'agent', 'type', 'sublandmark'],
    )->[0];

    # Prepare SMS for client
    if ($client->phone_num =~ /^9\d{9}$/) {
        my $rt_param = Rplus::Model::RuntimeParam->new(key => 'notifications')->load();
        my $contact_info = '';
        if ($rt_param) {
            my $config = from_json($rt_param->{value});
            $contact_info = $config->{'contact_info'} ? $config->{'contact_info'} : '';
        }        
        # TODO: Add template settings
        my @parts;
        {
            push @parts, $realty->type->name;
            push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
            push @parts, $realty->address_object->name.' '.$realty->address_object->short_type.($realty->address_object->name !~ /[()]/ && $realty->sublandmark ? ' ('.$realty->sublandmark->name.')' : '') if $realty->address_object;
            push @parts, ($realty->floor || '?').'/'.($realty->floors_count || '?').' эт.' if $realty->floor || $realty->floors_count;
            push @parts, $realty->price.' тыс. руб.' if $realty->price;
            push @parts, $realty->agent->public_name || $realty->agent->name if $realty->agent;
            push @parts, $realty->agent->public_phone_num || $realty->agent->phone_num if $realty->agent;
        }
        my $sms_body = join(', ', @parts);
        $sms_text = 'Вы интересовались: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.').$contact_info;

        $status = Rplus::Util::SMS->send($self, $client->phone_num, $sms_text);
    }

    return $self->render(json => {status => $status,});
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
        with_objects => ['address_object', 'agent', 'type', 'sublandmark'],
    )->[0];

    # Prepare SMS for client
    if ($client->email) {
        my $rt_param = Rplus::Model::RuntimeParam->new(key => 'notifications')->load();
        my $contact_info = '';
        if ($rt_param) {
            my $config = from_json($rt_param->{value});
            $contact_info = $config->{'contact_info'} ? $config->{'contact_info'} : '';
        }
        my @photos;
        my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $realty->id, delete_date => undef], sort_by => 'is_main DESC, id ASC');
        while (my $photo = $photo_iter->next) {
            push @photos, $photo->thumbnail_filename;
        }        
        # TODO: Add template settings
        my $message = get_digest($realty, \@photos);

        $status = Rplus::Util::Email->send($self, $client->email, $message);
    }

    return $self->render(json => {status => $status,});
}

sub get_digest {
    my $r = shift;
    my $photos = shift;

    my @digest;

    push @digest, '<strong>' . $r->type->name . '</strong>';
    push @digest, $r->rooms_count . 'к' if ($r->rooms_count);
    if ($r->address_object) {
        push @digest, $r->address_object->name . ' ' . $r->address_object->short_type . '. ' . ($r->house_num ? $r->house_num : '') . ($r->sublandmark ? ' (' . $r->sublandmark->name . ')' : '');
        #push @digest, $r->address_object->addr_parts->[1]->name . ' ' . $r->address_object->addr_parts->[1]->short_type;
    }
    if ($r->ap_scheme) {
        push @digest, $r->ap_scheme->metadata ? from_json($r->ap_scheme->metadata)->{description} : $r->ap_scheme->name;
    }
    if ($r->house_type) {
        #push @digest, $r->house_type->metadata ? from_json($r->house_type->metadata)->{description} : $r->house_type->name;
        push @digest, $r->house_type->name;
    }
    if ($r->room_scheme) {
        #push @digest, $r->room_scheme->metadata ? from_json($r->room_scheme->metadata)->{description} : $r->room_scheme->name;
        push @digest, $r->room_scheme->name;
    }
    if ($r->floor && $r->floors_count) {
        push @digest, $r->floor . '/' . $r->floors_count . ' эт.';
    } elsif ($r->floor || $r->floors_count) {
        push @digest, $r->floor || $r->floors_count . ' эт.';
    }

    if ($r->condition) {
        #push @digest, $r->condition->metadata ? from_json($r->condition->metadata)->{description} : $r->condition->name;
        push @digest, $r->condition->name;
    }
    if ($r->balcony) {
        #push @digest, $r->balcony->metadata ? from_json($r->balcony->metadata)->{description} : $r->balcony->name;
        push @digest, $r->balcony->name;
    }
    if ($r->bathroom) {
        #push @digest, $r->bathroom->metadata ? from_json($r->bathroom->metadata)->{description} : $r->bathroom->name;
        push @digest, $r->bathroom->name;
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
            push @digest, ((join '/', @squares) . ' кв. м.');
        }
    }

    if ($r->square_land && $r->square_land_type) {
        push @digest, $r->square_land . ' ' . ($r->square_land_type eq 'ar' ? 'сот.' : 'га');
    }
    if ($r->description) {
        push @digest, $r->description;
    }
    if ($r->price) {
        push @digest, '<br><span style="color: #428bca;">' . $r->price . ' тыс. руб.</span>';
    }
    #if (r.agent_id) {
    #if (r.agent_id == 10000) {
    #  digest.push('<br><span>Посредник: ' + r.mediator_company + '</span>');
    #} else {
    #  var agent = Rplus.Table.users[r.agent_id];
    #  digest.push('<br><span>Агент: ' + (agent.public_name || agent.name) + ', ' + (agent.public_phone_num || Rplus.Util.formatPhoneNum(Rplus.Table.users[r.agent_id].phone_num)) + '</span>');
    #}
    #} else {
    #digest.push('<br><span>Собственник</span>');
    #}
    #return digest.join(', ');
    push @digest, '</div>';

    my $message = $template_head;
    $message .= join ', ', @digest;
    foreach(@$photos) {
        $message .= "<img style=\"margin-top: 10px; margin-bottom: 10px;\" width=\"80%\" src=\"$_\">";
    }

    $message .= $template_tail;
    return $message;
}

1;


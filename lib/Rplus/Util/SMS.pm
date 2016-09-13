package Rplus::Util::SMS;

use Rplus::Modern;

use Rplus::Model::SmsMessage;
use Rplus::Model::SmsMessage::Manager;

use Mojo::UserAgent;
use JSON;

use Exporter qw(import);

our @EXPORT_OK = qw(prepare_sms_text enqueue send_sms);

sub prepare_sms_text {
    my ($realty, $for, $client, $acc_id, $send_owner_phone) = @_;
    my $sms_text = '';

    my $contact_info = '';
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    if ($options) {
        my $opt = from_json($options->{options})->{'notifications'};
        $contact_info = $opt->{'contact_info'} ? $opt->{'contact_info'} : '';
    }

    if ($for eq 'CLIENT') {
        # TODO: Add template settings
        my @parts;
        {
            push @parts, $realty->type->name;
            push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
            push @parts, $realty->locality.', '.$realty->address if $realty->address && $realty->locality;
            push @parts, $realty->district if $realty->district;
            push @parts, ($realty->floor || '?').'/'.($realty->floors_count || '?').' эт.' if $realty->floor || $realty->floors_count;
            push @parts, $realty->price.' тыс. руб.' if $realty->price;

            if ($send_owner_phone) {
                push @parts, "Собственник: ".join(', ', $realty->owner_phones);
            } elsif ($realty->agent) {
                push @parts, "Агент: ".($realty->agent->public_name || $realty->agent->name);
                push @parts, $realty->agent->public_phone_num || $realty->agent->phone_num;
            }
        }
        my $sms_body = join(', ', @parts);
        $sms_text = 'Вы интересовались: '.$sms_body.($sms_body =~ /\.$/ ? '' : '.') . ' ' . $contact_info;
    } else {
        # TODO: Add template settings
        my @parts;
        {
            push @parts, $realty->type->name;
            push @parts, $realty->rooms_count.'к' if $realty->rooms_count;
            push @parts, $realty->locality.', '.$realty->address.' '.$realty->house_num if $realty->address && $realty->locality;
            push @parts, $realty->price.' тыс. руб.' if $realty->price;
            push @parts, 'Клиент: '.$client->phone_num;
        }
        my $sms_text = join(', ', @parts);
    }

    return $sms_text;
}

sub enqueue {
    my ($phone_num, $sms_text, $acc_id) = @_;

    return Rplus::Model::SmsMessage->new(phone_num => $phone_num, text => $sms_text, account_id => $acc_id)->save;
}

sub send_sms {
    my ($phone_num, $message_text, $acc_id) = @_;

    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    my $config;
    if ($options) {
        $config = from_json($options->{options})->{notifications};
    }

    return 'not activated' unless $config->{active};

    my $sms = Rplus::Model::SmsMessage->new(phone_num => $phone_num, text => $message_text, account_id => $acc_id,)->save;

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->post('https://smsc.ru/sys/send.php' => form => {
        login => $config->{login},
        psw => $config->{password},
        ($config->{tz} ? (tz => $config->{tz}) : ()),
        ($config->{company} ? (sender => $config->{company}) : ()),
        phones => '+7'.$phone_num,
        mes => $message_text,
        id => $sms->id,
        charset => 'utf-8',
        cost => 2,
        fmt => 3,
    });
    if (my $res  = $tx->success) {
        if (my $x = $res->json) {
            if ($x->{'error_code'}) {
                $sms->status('error');
                $sms->last_error_msg(sprintf("(%s) %s", $x->{'error_code'}, $x->{'error'}));
            } else {
                $sms->status('sent');
            }
        } else {
            $sms->status('error');
            $sms->last_error_msg("Cannot parse a response as json");
        }
    } else {
        my ($err, $code) = $tx->error;
        $sms->status('error');
        $sms->last_error_msg($code ? "$code response: $err" : "Connection error: $err");
    }

    $sms->save;

    return $sms;
}

1;

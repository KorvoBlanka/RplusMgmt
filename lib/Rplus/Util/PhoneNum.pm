package Rplus::Util::PhoneNum;

use Rplus::Modern;

sub parse {
    my $class = shift;
    my $phone_num = shift;
    my $default_phone_prefix = shift || '';

    return unless $phone_num;

    if ($phone_num !~ /^\d{10}$/) {
        $phone_num =~ s/\D//g;
        $phone_num =~ s/^(7|8)(\d{10})$/$2/;
        $phone_num = $default_phone_prefix.$phone_num if "$default_phone_prefix$phone_num" =~ /^\d{10}$/;
        return unless $phone_num =~ /^\d{10}$/;
    }

    return $phone_num;
}

1;

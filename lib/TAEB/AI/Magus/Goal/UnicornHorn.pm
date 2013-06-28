package TAEB::AI::Magus::Goal::UnicornHorn;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->has_item('unicorn horn') }

1;


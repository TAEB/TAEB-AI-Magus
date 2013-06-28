package TAEB::AI::Magus::Goal::Instrument;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->has_item(tonal => 1) }

1;


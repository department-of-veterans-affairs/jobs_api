require 'spec_helper'

describe UsajobsData do
  let(:importer) { UsajobsData.new('doc/sample.xml') }
  let(:far_away) { Date.parse('2022-01-31') }
  let(:ttl) { "#{(far_away - Date.current).to_i}d" }

  describe '#import' do

    it 'should load the PositionOpenings from filename' do
      PositionOpening.should_receive(:import) do |position_openings|
        position_openings.length.should == 3
        position_openings[0].should ==
          {type: 'position_opening', source: 'usajobs', external_id: 305972200, _ttl: ttl,
           position_title: 'Medical Officer', tags: %w(federal),
           organization_id: 'AF09', organization_name: 'Air Force Personnel Center',
           locations: [{city: 'Dyess AFB', state: 'TX'}],
           start_date: Date.parse('2011-12-28'), end_date: far_away,
           minimum: 60274, maximum: 155500, rate_interval_code: 'PA', position_schedule_type_code: 1, position_offering_type_code: 15327}
        position_openings[1].should ==
          {type: 'position_opening', source: 'usajobs', external_id: 325054900, _ttl: ttl,
           position_title: 'Physician (Surgical Critical Care)', tags: %w(federal),
           organization_id: 'VATA', organization_name: 'Veterans Affairs, Veterans Health Administration',
           locations: [{city: 'Charleston', state: 'SC'}],
           start_date: Date.parse('27 Aug 2012'), end_date: far_away,
           minimum: 125000, maximum: 295000, rate_interval_code: 'PA', position_schedule_type_code: 2, position_offering_type_code: 15317}
        position_openings[2].should ==
          {type: 'position_opening', source: 'usajobs', external_id: 327358300, _ttl: ttl,
           position_title: 'Student Nurse Technicians', tags: %w(federal),
           organization_id: 'VATA', organization_name: 'Veterans Affairs, Veterans Health Administration',
           locations: [{city: 'Odessa', state: 'TX'},
                       {city: 'Pentagon, Arlington', state: 'VA'},
                       {city: 'San Angelo', state: 'TX'},
                       {city: 'Abilene', state: 'TX'}],
           start_date: Date.parse('19 Sep 2012'), end_date: far_away,
           minimum: 17, maximum: 23, rate_interval_code: 'PH', position_schedule_type_code: 2, position_offering_type_code: 15522}
      end
      importer.import
    end

    context 'when records have been somehow marked as inactive/closed/expired' do
      let(:anti_importer) { UsajobsData.new('spec/resources/usajobs/anti_sample.xml') }

      it 'should load the records with a ttl of 1s' do
        PositionOpening.should_receive(:import) do |position_openings|
          position_openings.length.should == 3
          position_openings[0].should ==
            {type: 'position_opening', source: 'usajobs', external_id: 305972200, _ttl: '1s',
             tags: %w(federal), locations: [{:city => "Dyess AFB", :state => "TX"}]}
          position_openings[1].should ==
            {type: 'position_opening', source: 'usajobs', external_id: 325054900, _ttl: '1s',
             tags: %w(federal), locations: [{:city => "Charleston", :state => "SC"}]}
          position_openings[2].should ==
            {type: 'position_opening', source: 'usajobs', external_id: 327358300, _ttl: '1s',
             tags: %w(federal), locations: [{:city => "Odessa", :state => "TX"},
                                            {:city => "Pentagon, Arlington", :state => "VA"},
                                            {:city => "San Angelo", :state => "TX"},
                                            {:city => "Abilene", :state => "TX"}]}
        end
        anti_importer.import
      end

    end

    context 'when location is invalid/empty' do
      let(:bad_location_importer) { UsajobsData.new('spec/resources/usajobs/bad_locations.xml') }

      it 'should ignore the location' do
        PositionOpening.should_receive(:import) do |position_openings|
          position_openings.length.should == 2
          position_openings[0].should ==
            {type: "position_opening", source: 'usajobs', external_id: 305972200, _ttl: ttl, position_title: "Medical Officer",
             organization_id: "AF09", organization_name: "Air Force Personnel Center", tags: %w(federal),
             locations: [{:city => "Fulton", :state => "MD"}],
             start_date: Date.parse('28 Dec 2011'), end_date: far_away,
             minimum: 60274, maximum: 155500, rate_interval_code: "PA", position_schedule_type_code: 1, position_offering_type_code: 15327}
          position_openings[1].should ==
            {type: "position_opening", source: 'usajobs', external_id: 325054900, _ttl: "1s", locations: [], tags: %w(federal)}
        end
        bad_location_importer.import
      end
    end

    context 'when too many locations are present for job (typical of recruiting announcements)' do
      let(:recruiting_importer) { UsajobsData.new('spec/resources/usajobs/recruiting_sample.xml') }

      it 'should load the records with a ttl of 1s and empty locations array' do
        PositionOpening.should_receive(:import) do |position_openings|
          position_openings.length.should == 1
          position_openings[0].should ==
            {type: 'position_opening', source: 'usajobs', external_id: 327358300, _ttl: '1s',
             tags: %w(federal), locations: []}
        end
        recruiting_importer.import
      end
    end
  end

  describe '#normalize_location(location_str)' do
    context 'when it looks like city-comma-the long form of a state name' do
      it 'should map it to the abbreviation' do
        importer.normalize_location('Vancouver, Washington').should == 'Vancouver, WA'
      end
    end

    context 'when it is some Puerto Rico variant' do
      it 'should normalize to city, PR' do
        location_strs = ['City Puerto Rico', 'City, PR Puerto Rico']
        location_strs.each { |location_str| importer.normalize_location(location_str).should == 'City, PR' }
      end
    end

    context 'when it is some Guam variant' do
      it 'should normalize to city, GQ' do
        location_strs = ['City Guam', 'City, GQ Guam']
        location_strs.each { |location_str| importer.normalize_location(location_str).should == 'City, GQ' }
      end
    end

    context 'when it is some basic DC variant' do
      it 'should normalize to Washington, DC' do
        location_strs = ['Washington DC, DC United States',
                         'Washington, DC, US',
                         'Washington DC, DC',
                         'District Of Columbia County, DC, US',
                         'District of Columbia, DC United States',
                         'Dist. of Columbia, DC United States',
                         'Dist of Columbia, DC United States',
                         'Washington, Dist of Columbia',
                         'Washington, District of Columbia',
                         'Washington, Dist. of Columbia',
                         'Washington, DC',
                         'Washington, DC, Dist of Columbia',
                         'Washington DC',
                         'Washington D.C.',
                         'Washington DC, US',
                         'District Of Columbia, US']
        location_strs.each { |location_str| importer.normalize_location(location_str).should == 'Washington, DC' }
      end
    end

    context 'when it is some DC Metro variant' do
      it 'should normalize to Washington Metro Area, DC' do
        location_strs = ['Washington DC Metro Area, DC United States', 'Washington DC Metro Area, DC, US',
                         'Washington DC Metro Area, DC']
        location_strs.each { |location_str| importer.normalize_location(location_str).should == 'Washington Metro Area, DC' }
      end
    end

    context 'when it is some Central Office DC variant' do
      it 'should normalize to Central Office, Washington, DC' do
        location_strs = ['Central Office, Washington DC, US', 'Central Office, Washington, DC',
                         'Central Office, Washington DC']
        location_strs.each { |location_str| importer.normalize_location(location_str).should == 'Central Office, Washington, DC' }
      end
    end

    context 'when it contains parens' do
      it 'should remove them' do
        importer.normalize_location('Suburb, (Suitland, MD)').should == 'Suburb, Suitland, MD'
      end
    end

    context 'when it refers to the Arizona Strip' do
      it 'should strip that out' do
        importer.normalize_location('Saint George, UT, US Arizona Strip').should == 'Saint George, UT'
      end
    end

    context 'when there is no match' do
      it 'should just return the string unchanged' do
        importer.normalize_location('FAA Air Traffic Control Locations').should == 'FAA Air Traffic Control Locations'
      end
    end
  end
end
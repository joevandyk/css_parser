module CssParser # :nodoc:
  class RuleSet
    # Patterns for specificity calculations
    RE_ELEMENTS_AND_PSEUDO_ELEMENTS = /((^|[\s\+\>]+)[\w]+|\:(first\-line|first\-letter|before|after))/i
    RE_NON_ID_ATTRIBUTES_AND_PSEUDO_CLASSES = /(\.[\w]+)|(\[[\w]+)|(\:(link|first\-child|lang))/i

    attr_reader   :selectors, :block, :specificity

    def initialize(selectors, block, specificity = nil)
      @selectors = selectors
      @block = block
      @specificity = specificity
      @declarations = {}
      parse_declarations!
      #expand_shorthand!
    end

    # Append a declaration to the current RuleSet.
    def add_declaration!(property, value)
      @declarations[property] = value
      parse_declarations!
    end

    # Iterate through selectors.
    #
    # Options
    # -  +force_important+ -- boolean
    # -  +media+
    #
    # ==== Example
    #   ruleset.each_selector(:media => :print) do |sel, dec, spec|
    #     ...
    #   end
    def each_selector(options = {}) # :yields: selector, declarations, specificity
      declarations = declarations_to_s(options)
      if @specificity
        @selectors.split(',').each { |sel| yield sel.strip, declarations, @specificity }
      else
        @selectors.split(',').each { |sel| yield sel.strip, declarations, Parser.calculate_specificity(sel) }
      end
    end

    # Iterate through declarations.
    def each_declaration # :yields: property, value, is_important
      @declarations.each do |property, data|
        value = data[:value]
        #value += ' !important' if data[:is_important]
        yield property.downcase.strip, value.strip, data[:is_important]
      end
    end

    # Return all declarations as a string.
    #
    #--
    # TODO: Clean-up regexp doesn't seem to work
    #++
    def declarations_to_s(options = {})
     options = {:force_important => false}.merge(options)
     str = ''
     importance = options[:force_important] ? ' !important' : ''
     each_declaration { |prop, val| str += "#{prop}: #{val}#{importance}; " }
     str.gsub(/^[\s]+|[\n\r\f\t]*|[\s]+$/mx, '').strip
    end

    # Split shorthand declarations (e.g. +margin+ or +font+) into their constituent parts.
    def expand_shorthand!
      parse_declarations! if @declarations.empty?

      expand_shorthand_dimensions!
      expand_font_shorthand!
      expand_background_shorthand!
    end

    # Escape declarations for use in inline <tt>style</tt> attributes.
    def escape_declarations!
      #if str =~ CssParser::RE_STRING1
      #  puts "#{str} is double quoted"
      #end
      @declarations.gsub!(/\"/, "'")
    end

private
    def parse_declarations!
      @declarations = {}

      return unless @block

      @block.split(/[\;$]+/m).each do |decs|
        if matches = decs.match(/(.[^:]*)\:(.[^;]*)(;|\Z)/i)
          property, value, end_of_declaration = matches.captures

          property.downcase!
          property.strip!
          value.strip!

          is_important = !value.gsub!(CssParser::IMPORTANT_IN_PROPERTY_RX, '').nil?

          @declarations[property] = {:value => value, :is_important => is_important}
        end
      end
    end

    # Split shorthand dimensional declarations (e.g. <tt>margin: 0px auto;</tt>)
    # into their constituent parts.
    def expand_shorthand_dimensions!
      ['margin', 'padding'].each do |property|

        next unless @declarations.has_key?(property)
        
        value = @declarations[property][:value]
        is_important = @declarations[property][:is_important]
        t, r, b, l = nil

        matches = value.scan(CssParser::BOX_MODEL_UNITS_RX)

        case matches.length
          when 1
            t, r, b, l = matches[0][0], matches[0][0], matches[0][0], matches[0][0]
          when 2
            t, b = matches[0][0], matches[0][0]
            r, l = matches[1][0], matches[1][0]
          when 3
            t =  matches[0][0]
            r, l = matches[1][0], matches[1][0]
            b =  matches[2][0]
          when 4
            t =  matches[0][0]
            r = matches[1][0]
            b =  matches[2][0]
            l = matches[3][0]
        end

        @declarations["#{property}-top"] = {:value => t.to_s, :is_important => is_important}
        @declarations["#{property}-right"] = {:value => r.to_s, :is_important => is_important}
        @declarations["#{property}-bottom"] = {:value => b.to_s, :is_important => is_important}
        @declarations["#{property}-left"] = {:value => l.to_s, :is_important => is_important}
        @declarations.delete(property)
      end
    end

    # Convert shorthand font declarations (e.g. <tt>font: 300 italic 11px/14px verdana, helvetica, sans-serif;</tt>)
    # into their constituent parts.
    def expand_font_shorthand!
      return unless @declarations.has_key?('font')

      font_props = {}

      # reset properties to 'normal' per http://www.w3.org/TR/CSS21/fonts.html#font-shorthand
      ['font-style', 'font-variant', 'font-weight', 'font-size',
       'line-height'].each do |prop|
        font_props[prop] = 'normal'
       end

      value = @declarations['font'][:value]
      is_important = @declarations['font'][:is_important]

      in_fonts = false

      matches = value.scan(/("(.*[^"])"|'(.*[^'])'|(\w[^ ,]+))/)
      matches.each do |match|
        m = match[0].to_s.strip
        m.gsub!(/[;]$/, '')

        if in_fonts
          if font_props.has_key?('font-family')
            font_props['font-family'] += ', ' + m
          else
            font_props['font-family'] = m
          end
        elsif m =~ /normal|inherit/i
          ['font-style', 'font-weight', 'font-variant'].each do |font_prop|
            font_props[font_prop] = m unless font_props.has_key?(font_prop)
          end
        elsif m =~ /italic|oblique/i
          font_props['font-style'] = m
        elsif m =~ /small\-caps/i
          font_props['font-variant'] = m
        elsif m =~ /[1-9]00$|bold|bolder|lighter/i
          font_props['font-weight'] = m
        elsif m =~ CssParser::FONT_UNITS_RX
          if m =~ /\//
            font_props['font-size'], font_props['line-height'] = m.split('/')
          else
            font_props['font-size'] = m
          end
          in_fonts = true
        end
      end

      font_props.each { |font_prop, font_val| @declarations[font_prop] = {:value => font_val, :is_important => is_important} }

      @declarations.delete('font')
    end


    # Convert shorthand background declarations (e.g. <tt>background: url("chess.png") gray 50% repeat fixed;</tt>)
    # into their constituent parts.
    #
    # See http://www.w3.org/TR/CSS21/colors.html#propdef-background
    def expand_background_shorthand!
      return unless @declarations.has_key?('background')

      value = @declarations['background'][:value]
      is_important = @declarations['background'][:is_important]

      bg_props = {}

      if m = value.match(/([\s]*^)?(scroll|fixed)([\s]*$)?/i).to_s
        bg_props['background-attachment'] = m.strip unless m.empty?
      end

      if m = value.match(/([\s]*^)?(repeat(\-x|\-y)*|no\-repeat)([\s]*$)?/i).to_s
        bg_props['background-repeat'] = m.strip unless m.empty?
      end

      if m = value.match(CssParser::RE_COLOUR).to_s
        bg_props['background-color'] = m.strip unless m.empty?
      end

      value.scan(CssParser::RE_BACKGROUND_POSITION).each do |m|
        if bg_props.has_key?('background-position')
          bg_props['background-position'] += ' ' + m[0].to_s.strip unless m.empty?
        else
          bg_props['background-position'] =  m[0].to_s.strip unless m.empty?
        end
      end

      if m = value.match(Regexp.union(CssParser::URI_RX, /none/i)).to_s
        bg_props['background-image'] = m.strip unless m.empty?
      end

      if value =~ /([\s]*^)?inherit([\s]*$)?/i
        ['background-color', 'background-image', 'background-attachment', 'background-repeat', 'background-position'].each do |prop|
            bg_props["#{prop}"] = 'inherit' unless bg_props.has_key?(prop) and not bg_props[prop].empty?
        end
      end

      bg_props.each { |bg_prop, bg_val| @declarations[bg_prop] = {:value => bg_val, :is_important => is_important} }

      @declarations.delete('background')
    end

  end
end